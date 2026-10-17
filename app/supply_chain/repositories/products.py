from decimal import Decimal

from ..models import NewProduct, Product, ProductCategory
from .base import Repository


class ProductRepository(Repository):
    _SELECT = ("SELECT sku, name, price, category, warranty_months, size, material, total_stock "
               "FROM scm.v_product")

    def get_by_sku(self, sku: str) -> Product | None:
        return self._query_one(self._SELECT + " WHERE sku = %s", Product, (sku,))

    def get_all(self, category: ProductCategory | None = None) -> list[Product]:
        if category is None:
            return self._query(self._SELECT + " ORDER BY sku", Product)
        return self._query(self._SELECT + " WHERE category = %s ORDER BY sku", Product, (category,))

    def create(self, p: NewProduct) -> None:
        self._execute("CALL scm.sp_product_create(%s, %s, %s, %s, %s, %s, %s)",
                      (p.sku, p.name, p.price, p.category, p.warranty_months, p.size, p.material))

    def update(self, sku: str, name: str, price: Decimal, warranty_months: int | None = None,
               size: str | None = None, material: str | None = None) -> None:
        self._execute("CALL scm.sp_product_update(%s, %s, %s, %s, %s, %s)",
                      (sku, name, price, warranty_months, size, material))

    def delete(self, sku: str) -> None:   # soft delete
        self._execute("CALL scm.sp_product_delete(%s)", (sku,))

    def restore(self, sku: str) -> None:
        self._execute("CALL scm.sp_product_restore(%s)", (sku,))
