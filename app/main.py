import io
import sys
from dataclasses import replace
from datetime import datetime
from decimal import Decimal

import psycopg

from supply_chain import UnitOfWork, UnitOfWorkFactory
from supply_chain.config import Settings, load_settings
from supply_chain.models import AppUser, OrderItem, OrderStatus, ShipmentStatus, StockItem


def require[T](value: T | None, what: str) -> T:
    if value is None:
        raise LookupError(f"{what} не знайдено")
    return value


def money(value: Decimal) -> str:
    return f"{value:,.2f}".replace(",", " ").replace(".", ",")


def local_time(value: datetime | None, fmt: str = "%H:%M:%S") -> str:
    return value.astimezone().strftime(fmt) if value else "-"


def header(title: str) -> None:
    print(f"\n=== {title} ===")


class Demo:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.uow = UnitOfWorkFactory(settings.connection, on_notice=lambda msg: print(f"   [NOTICE] {msg}"))
        self.stamp = datetime.now().strftime("%H%M%S")

    def run(self) -> None:
        sales = self.require_user(self.settings.users.sales)
        store = self.require_user(self.settings.users.store)
        manager = self.require_user(self.settings.users.manager)
        if sales.employee_id is None:
            raise LookupError(f"Користувач {sales.username} не прив'язаний до працівника")

        self.show_catalog()
        placed = self.place_order(sales.id, sales.employee_id)
        if placed is None:
            return
        customer_id, order_number = placed
        self.ship_order(store.id, order_number)
        self.atomic_rollback(sales.id, sales.employee_id)
        self.soft_delete_and_audit(manager.id, customer_id)

    def show_catalog(self) -> None:
        header("1. Каталог і залишки (читання з представлень)")
        with self.uow.begin_read_only() as uow:
            for p in uow.products.get_all():
                print(f"   {p.sku:<13} {p.name:<25} {money(p.price):>10} грн  {p.category:<11} "
                      f"на складах: {p.total_stock}")
            print()
            for s in uow.stock.get_all():
                print(f"   {s.warehouse_name:<18} {s.product_sku:<13} {s.quantity:>5} шт.")

    def place_order(self, user_id: int, employee_id: int) -> tuple[int, int] | None:
        header(f"2. Новий клієнт і замовлення ({self.settings.users.sales}, один Unit of Work)")
        first_qty, second_qty, extra_qty = 2, 10, 5

        with self.uow.begin(user_id) as uow:
            # два товари, яких вистачає на одному складі
            by_warehouse: dict[int, list[StockItem]] = {}
            for s in uow.stock.get_all():
                if s.quantity >= second_qty + extra_qty:
                    by_warehouse.setdefault(s.warehouse_id, []).append(s)
            pair = next((items[:2] for items in by_warehouse.values() if len(items) >= 2), None)
            if pair is None:
                print("   Немає складу з двома товарами в достатній кількості — сценарій пропущено")
                return None
            first, second = pair
            other = next(p for p in uow.products.get_all()
                         if p.sku not in (first.product_sku, second.product_sku))

            phone = f"+38044{self.stamp}0"
            existing = uow.customers.find_by_phone(phone)
            customer_id = existing.id if existing else uow.customers.create(
                f'ТОВ "Демо-{self.stamp}"', phone, f"demo{self.stamp}@example.com",
                "м. Київ, вул. Лабораторна, 7")
            order_number = uow.orders.create(customer_id, employee_id)

            uow.orders.add_item(order_number, first.product_sku, first_qty)
            uow.orders.add_item(order_number, second.product_sku, second_qty)
            other_line = uow.orders.add_item(order_number, other.sku, 1)
            line = uow.orders.add_item(order_number, second.product_sku, extra_qty)   # той самий товар -> +5
            print(f"   {second.product_name}: повторне додавання збільшило кількість у рядку {line}")

            uow.orders.remove_item(order_number, other_line)
            print(f"   {other.name}: рядок {other_line} видалено")

            uow.orders.set_status(order_number, OrderStatus.CONFIRMED)

            # у тій самій транзакції видно незафіксовані зміни
            self.print_order(uow, order_number)
            uow.commit()
        print(f"   COMMIT: клієнт #{customer_id}, замовлення #{order_number}")
        return customer_id, order_number

    def ship_order(self, user_id: int, order_number: int) -> None:
        header(f"3. Відвантаження замовлення ({self.settings.users.store})")

        with self.uow.begin(user_id) as uow:
            items = uow.orders.get_items(order_number)
            warehouses = list(dict.fromkeys(s.warehouse_id for s in uow.stock.get_all()))

            suitable = next((w for w in warehouses
                             if all(uow.stock.get_available(i.product_sku, w) >= i.quantity for i in items)),
                            None)
            if suitable is None:
                print("   Немає складу з достатнім залишком — ROLLBACK")
                return

            # спершу інший склад, щоб показати sp_shipment_set_warehouse
            initial = next((w for w in warehouses if w != suitable), suitable)
            shipment_id = uow.shipments.create(order_number, initial, f"NP-{self.stamp}")
            print(f"   Створено відвантаження #{shipment_id} зі складу id {initial}")
            if initial != suitable:
                uow.shipments.change_warehouse(shipment_id, suitable)
                print(f"   На складі id {initial} бракує товару — склад змінено на id {suitable}")

            before = self.stock_of(uow, items, suitable)
            uow.shipments.set_status(shipment_id, ShipmentStatus.SHIPPED)     # тригер списує залишки
            uow.shipments.set_status(shipment_id, ShipmentStatus.DELIVERED)
            after = self.stock_of(uow, items, suitable)
            uow.commit()

        with self.uow.begin_read_only() as uow:
            shipment = require(uow.shipments.get(shipment_id), f"Відвантаження #{shipment_id}")
            order = require(uow.orders.get(order_number), f"Замовлення #{order_number}")
        print(f"   COMMIT: відвантаження #{shipment.id} ({shipment.warehouse_name}) — {shipment.status}, "
              f"трек {shipment.tracking_number}, змінив {shipment.updated_by}")
        for item in items:
            print(f"   {item.product_sku:<13} залишок {before[item.product_sku]:>4} -> {after[item.product_sku]:>4}")
        print(f"   Замовлення #{order.order_number}: {order.status} (змінив {order.updated_by})")

    def atomic_rollback(self, user_id: int, employee_id: int) -> None:
        header("4. Атомарність: помилка -> ROLLBACK усіх сутностей")
        email = f"rollback{self.stamp}@example.com"

        with self.uow.begin(user_id) as uow:
            try:
                # на 1 шт. більше, ніж є на всіх складах
                stock = uow.stock.get_all()[0]
                too_many = uow.stock.get_available(stock.product_sku) + 1

                customer_id = uow.customers.create("Клієнт, якого не буде", None, email, None)
                order_number = uow.orders.create(customer_id, employee_id)
                uow.orders.add_item(order_number, stock.product_sku, too_many)
                uow.orders.set_status(order_number, OrderStatus.CONFIRMED)
                shipment_id = uow.shipments.create(order_number, stock.warehouse_id)
                print(f"   Створено клієнта #{customer_id}, замовлення #{order_number}, "
                      f"відвантаження #{shipment_id}")

                uow.shipments.set_status(shipment_id, ShipmentStatus.SHIPPED)
                uow.commit()
            except psycopg.errors.RaiseException as e:
                print(f"   Помилка: {e.diag.message_primary}")
                uow.rollback()
                print("   ROLLBACK")

        with self.uow.begin_read_only() as uow:
            found = uow.customers.find_by_email(email)
        print(f"   Клієнт {email} у БД: "
              f"{'відсутній — транзакцію відкочено повністю' if found is None else 'Є (!)'}")

    def soft_delete_and_audit(self, user_id: int, customer_id: int) -> None:
        header(f"5. Soft delete + аудит ({self.settings.users.manager})")

        with self.uow.begin(user_id) as uow:
            c = require(uow.customers.get_by_id(customer_id), f"Клієнта #{customer_id}")
            uow.customers.update(replace(c, address=f"{c.address} (оновлено)"))
            uow.customers.delete(customer_id)
            uow.commit()

        with self.uow.begin_read_only() as uow:
            visible = uow.customers.get_by_id(customer_id)
            deleted = next(d for d in uow.customers.get_deleted() if d.record_id == str(customer_id))
        print(f"   Після видалення v_customer повертає: {visible.full_name if visible else None}")
        print(f"   Кошик: {deleted.title}, видалив {deleted.deleted_by} о {local_time(deleted.deleted_at)}")

        with self.uow.begin(user_id) as uow:
            uow.customers.restore(customer_id)
            uow.commit()

        with self.uow.begin_read_only() as uow:
            restored = require(uow.customers.get_by_id(customer_id), f"Клієнта #{customer_id}")
            history = uow.customers.get_history(customer_id)
        print(f"   Відновлено: {restored.full_name}, {restored.address}, "
              f"змінив {restored.updated_by} о {local_time(restored.updated_at)}")
        print("   Історія змін клієнта (fn_record_history):")
        for h in history:
            print(f"     {local_time(h.changed_at, '%H:%M:%S.%f')[:-3]}  {h.operation:<12} {h.username}")

    def require_user(self, username: str) -> AppUser:
        with self.uow.begin_read_only() as uow:
            user = uow.users.get_by_username(username)
        if user is None:
            raise LookupError(f"Активного користувача '{username}' не знайдено")
        return user

    @staticmethod
    def stock_of(uow: UnitOfWork, items: list[OrderItem], warehouse_id: int) -> dict[str, int]:
        return {i.product_sku: uow.stock.get_available(i.product_sku, warehouse_id) for i in items}

    @staticmethod
    def print_order(uow: UnitOfWork, order_number: int) -> None:
        order = require(uow.orders.get(order_number), f"Замовлення #{order_number}")
        print(f"   Замовлення #{order.order_number} [{order.status}] клієнт: {order.customer_name}, "
              f"менеджер: {order.employee_name}")
        for i in uow.orders.get_items(order_number):
            print(f"     {i.line_number}. {i.product_name:<25} {i.quantity:>3} x {money(i.unit_price):>9} "
                  f"= {money(i.line_total):>10}")
        print(f"     Разом (fn_order_total): {money(uow.orders.get_total(order_number))} грн")


def main(argv: list[str]) -> int:
    if isinstance(sys.stdout, io.TextIOWrapper):   # кирилиця в консолі Windows
        sys.stdout.reconfigure(encoding="utf-8")
    try:
        Demo(load_settings(argv)).run()
    except psycopg.Error as e:
        if e.sqlstate:
            print(f"\nПомилка БД [{e.sqlstate}]: {e.diag.message_primary}")
        else:
            print(f"\nНе вдалося підключитися до БД: {e}")
        return 1
    except LookupError as e:
        print(f"\nПомилка: {e}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
