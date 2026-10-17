from ..models import Shipment, ShipmentStatus
from .base import Repository


class ShipmentRepository(Repository):
    _SELECT = ("SELECT id, order_number, warehouse_id, warehouse_name, shipped_at, tracking_number, "
               "status, updated_at, updated_by_username AS updated_by FROM scm.v_shipment")

    def get(self, shipment_id: int) -> Shipment | None:
        return self._query_one(self._SELECT + " WHERE id = %s", Shipment, (shipment_id,))

    def get_by_order(self, order_number: int) -> Shipment | None:
        return self._query_one(self._SELECT + " WHERE order_number = %s", Shipment, (order_number,))

    def create(self, order_number: int, warehouse_id: int, tracking_number: str | None = None) -> int:
        return self._scalar("CALL scm.sp_shipment_create(%s, %s, %s, NULL)",
                            (order_number, warehouse_id, tracking_number))

    def change_warehouse(self, shipment_id: int, warehouse_id: int) -> None:
        self._execute("CALL scm.sp_shipment_set_warehouse(%s, %s)", (shipment_id, warehouse_id))

    def set_status(self, shipment_id: int, status: ShipmentStatus) -> None:
        self._execute("CALL scm.sp_shipment_set_status(%s, %s)", (shipment_id, status))
