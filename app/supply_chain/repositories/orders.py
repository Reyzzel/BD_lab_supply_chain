from decimal import Decimal

from ..models import Order, OrderItem, OrderStatus
from .base import Repository


class OrderRepository(Repository):
    _SELECT = ("SELECT order_number, order_date, status, customer_id, customer_name, "
               "employee_id, employee_name, items_count, total_amount, shipment_id, shipment_status, "
               "updated_at, updated_by_username AS updated_by FROM scm.v_order_summary")

    def get(self, order_number: int) -> Order | None:
        return self._query_one(self._SELECT + " WHERE order_number = %s", Order, (order_number,))

    def get_by_customer(self, customer_id: int) -> list[Order]:
        return self._query(self._SELECT + " WHERE customer_id = %s ORDER BY order_number",
                           Order, (customer_id,))

    def get_items(self, order_number: int) -> list[OrderItem]:
        return self._query(
            "SELECT order_number, line_number, product_sku, product_name, quantity, unit_price, line_total "
            "FROM scm.v_order_item WHERE order_number = %s ORDER BY line_number",
            OrderItem, (order_number,))

    def get_total(self, order_number: int) -> Decimal:
        return self._scalar("SELECT scm.fn_order_total(%s)", (order_number,))

    def create(self, customer_id: int, employee_id: int) -> int:
        return self._scalar("CALL scm.sp_order_create(%s, %s, NULL)", (customer_id, employee_id))

    def add_item(self, order_number: int, sku: str, quantity: int) -> int:
        # якщо товар уже є в замовленні, збільшує кількість; повертає номер рядка
        return self._scalar("CALL scm.sp_order_add_item(%s, %s, %s, NULL)", (order_number, sku, quantity))

    def remove_item(self, order_number: int, line_number: int) -> None:
        self._execute("CALL scm.sp_order_remove_item(%s, %s)", (order_number, line_number))

    def set_status(self, order_number: int, status: OrderStatus) -> None:
        self._execute("CALL scm.sp_order_set_status(%s, %s)", (order_number, status))
