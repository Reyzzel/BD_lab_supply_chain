# Імена полів збігаються зі стовпцями SELECT (psycopg.rows.class_row)
from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal
from enum import StrEnum
from typing import Any


class UserRole(StrEnum):
    ADMIN = "admin"
    MANAGER = "manager"
    SALES = "sales"
    WAREHOUSE_WORKER = "warehouse_worker"


class ProductCategory(StrEnum):
    ELECTRONICS = "electronics"
    CLOTHING = "clothing"


class OrderStatus(StrEnum):
    NEW = "new"
    CONFIRMED = "confirmed"
    SHIPPED = "shipped"
    DELIVERED = "delivered"
    CANCELLED = "cancelled"


class ShipmentStatus(StrEnum):
    PENDING = "pending"
    SHIPPED = "shipped"
    DELIVERED = "delivered"


@dataclass(frozen=True, slots=True)
class AppUser:
    id: int
    username: str
    role: UserRole
    employee_id: int | None
    employee_name: str | None


@dataclass(frozen=True, slots=True)
class Customer:
    id: int
    full_name: str
    phone: str | None
    email: str | None
    address: str | None
    updated_at: datetime | None
    updated_by: str | None


@dataclass(frozen=True, slots=True)
class Product:
    sku: str
    name: str
    price: Decimal
    category: ProductCategory
    warranty_months: int | None
    size: str | None
    material: str | None
    total_stock: int


@dataclass(frozen=True, slots=True)
class Order:
    order_number: int
    order_date: datetime
    status: OrderStatus
    customer_id: int
    customer_name: str
    employee_id: int
    employee_name: str
    items_count: int
    total_amount: Decimal
    shipment_id: int | None
    shipment_status: ShipmentStatus | None
    updated_at: datetime | None
    updated_by: str | None


@dataclass(frozen=True, slots=True)
class OrderItem:
    order_number: int
    line_number: int
    product_sku: str
    product_name: str
    quantity: int
    unit_price: Decimal
    line_total: Decimal


@dataclass(frozen=True, slots=True)
class Shipment:
    id: int
    order_number: int
    warehouse_id: int
    warehouse_name: str
    shipped_at: datetime | None
    tracking_number: str | None
    status: ShipmentStatus
    updated_at: datetime | None
    updated_by: str | None


@dataclass(frozen=True, slots=True)
class StockItem:
    warehouse_id: int
    warehouse_name: str
    product_sku: str
    product_name: str
    quantity: int


@dataclass(frozen=True, slots=True)
class DeletedRecord:
    table_name: str
    record_id: str
    title: str
    deleted_at: datetime
    deleted_by: str | None


@dataclass(frozen=True, slots=True)
class HistoryEntry:
    changed_at: datetime
    operation: str
    username: str | None
    old_data: dict[str, Any] | None   # jsonb -> dict
    new_data: dict[str, Any] | None


@dataclass(frozen=True, slots=True)
class NewProduct:
    sku: str
    name: str
    price: Decimal
    category: ProductCategory
    warranty_months: int | None = None
    size: str | None = None
    material: str | None = None
