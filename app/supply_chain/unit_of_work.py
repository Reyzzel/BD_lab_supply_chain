from collections.abc import Callable
from enum import StrEnum
from functools import cached_property
from types import TracebackType
from typing import Self

import psycopg
from psycopg.types.enum import EnumInfo, register_enum

from .models import OrderStatus, ProductCategory, ShipmentStatus, UserRole
from .repositories import (CustomerRepository, OrderRepository, ProductRepository,
                           ShipmentRepository, StockRepository, UserRepository)

_ENUMS: dict[str, type[StrEnum]] = {
    "scm.user_role": UserRole,
    "scm.product_category": ProductCategory,
    "scm.order_status": OrderStatus,
    "scm.shipment_status": ShipmentStatus,
}


class UnitOfWork:
    # Одна бізнес-операція = одна транзакція. Без commit() зміни відкочуються.

    def __init__(self, factory: "UnitOfWorkFactory", user_id: int | None) -> None:
        self._factory = factory
        self._user_id = user_id
        self._conn: psycopg.Connection | None = None
        self._completed = False

    def __enter__(self) -> Self:
        conn = psycopg.connect(self._factory.conninfo)
        try:
            conn.read_only = self._user_id is None
            if (on_notice := self._factory.on_notice) is not None:
                conn.add_notice_handler(lambda d: on_notice(d.message_primary or ""))
            self._factory.register_enums(conn)
            if self._user_id is not None:
                conn.execute("CALL scm.sp_set_current_user(%s)", (self._user_id,))
        except BaseException:
            conn.close()
            raise
        self._conn = conn
        return self

    def __exit__(self, exc_type: type[BaseException] | None, exc: BaseException | None,
                 tb: TracebackType | None) -> None:
        conn = self._connection
        try:
            if not self._completed and not conn.broken:
                conn.rollback()
        finally:
            conn.close()

    @property
    def _connection(self) -> psycopg.Connection:
        if self._conn is None:
            raise RuntimeError("Unit of Work не відкрито: використовуйте 'with factory.begin(...) as uow'")
        return self._conn

    @cached_property
    def users(self) -> UserRepository:
        return UserRepository(self._connection)

    @cached_property
    def customers(self) -> CustomerRepository:
        return CustomerRepository(self._connection)

    @cached_property
    def products(self) -> ProductRepository:
        return ProductRepository(self._connection)

    @cached_property
    def orders(self) -> OrderRepository:
        return OrderRepository(self._connection)

    @cached_property
    def shipments(self) -> ShipmentRepository:
        return ShipmentRepository(self._connection)

    @cached_property
    def stock(self) -> StockRepository:
        return StockRepository(self._connection)

    def commit(self) -> None:
        self._ensure_active()
        self._completed = True
        self._connection.commit()   # перевіряються відкладені FK

    def rollback(self) -> None:
        self._ensure_active()
        self._completed = True
        self._connection.rollback()

    def _ensure_active(self) -> None:
        if self._completed:
            raise RuntimeError("Unit of Work вже завершено")


class UnitOfWorkFactory:
    def __init__(self, conninfo: str, on_notice: Callable[[str], None] | None = None) -> None:
        self.conninfo = conninfo
        self.on_notice = on_notice
        self._enum_infos: dict[str, EnumInfo] = {}

    def begin(self, user_id: int) -> UnitOfWork:
        return UnitOfWork(self, user_id)

    def begin_read_only(self) -> UnitOfWork:
        return UnitOfWork(self, None)

    def register_enums(self, conn: psycopg.Connection) -> None:
        if not self._enum_infos:
            for name in _ENUMS:
                info = EnumInfo.fetch(conn, name)
                if info is None:
                    raise LookupError(f"Тип {name} не знайдено — чи розгорнуто sql/01_schema.sql?")
                self._enum_infos[name] = info
        for name, enum in _ENUMS.items():
            register_enum(self._enum_infos[name], conn, enum, mapping={m: m.value for m in enum})
