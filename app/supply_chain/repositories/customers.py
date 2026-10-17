from ..models import Customer, DeletedRecord, HistoryEntry
from .base import Repository


class CustomerRepository(Repository):
    _SELECT = ("SELECT id, full_name, phone, email, address, updated_at, "
               "updated_by_username AS updated_by FROM scm.v_customer")

    def get_by_id(self, customer_id: int) -> Customer | None:
        return self._query_one(self._SELECT + " WHERE id = %s", Customer, (customer_id,))

    def find_by_email(self, email: str) -> Customer | None:
        return self._query_one(self._SELECT + " WHERE lower(email) = lower(%s)", Customer, (email,))

    # hash-індекс ix_customer_phone_hash
    def find_by_phone(self, phone: str) -> Customer | None:
        return self._query_one(self._SELECT + " WHERE phone = %s", Customer, (phone,))

    def get_all(self) -> list[Customer]:
        return self._query(self._SELECT + " ORDER BY id", Customer)

    def get_deleted(self) -> list[DeletedRecord]:
        return self._query(
            "SELECT table_name, record_id, title, deleted_at, deleted_by FROM scm.v_deleted_records "
            "WHERE table_name = 'customer' ORDER BY deleted_at",
            DeletedRecord)

    def get_history(self, customer_id: int) -> list[HistoryEntry]:
        return self._query(
            "SELECT changed_at, operation, username, old_data, new_data "
            "FROM scm.fn_record_history('customer', %s)",
            HistoryEntry, (str(customer_id),))

    def create(self, full_name: str, phone: str | None, email: str | None, address: str | None) -> int:
        return self._scalar("CALL scm.sp_customer_create(%s, %s, %s, %s, NULL)",
                            (full_name, phone, email, address))

    def update(self, customer: Customer) -> None:
        self._execute("CALL scm.sp_customer_update(%s, %s, %s, %s, %s)",
                      (customer.id, customer.full_name, customer.phone, customer.email, customer.address))

    def delete(self, customer_id: int) -> None:   # soft delete
        self._execute("CALL scm.sp_customer_delete(%s)", (customer_id,))

    def restore(self, customer_id: int) -> None:
        self._execute("CALL scm.sp_customer_restore(%s)", (customer_id,))
