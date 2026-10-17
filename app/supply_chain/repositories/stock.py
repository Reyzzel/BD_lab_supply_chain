from ..models import StockItem
from .base import Repository


class StockRepository(Repository):
    # залишки змінюють лише тригери supply / shipment
    _SELECT = "SELECT warehouse_id, warehouse_name, product_sku, product_name, quantity FROM scm.v_stock"

    def get_all(self) -> list[StockItem]:
        return self._query(self._SELECT + " ORDER BY warehouse_id, product_sku", StockItem)

    def get_by_product(self, sku: str) -> list[StockItem]:
        return self._query(self._SELECT + " WHERE product_sku = %s ORDER BY warehouse_id", StockItem, (sku,))

    def get_available(self, sku: str, warehouse_id: int | None = None) -> int:
        return self._scalar("SELECT scm.fn_stock_available(%s, %s)", (sku, warehouse_id))
