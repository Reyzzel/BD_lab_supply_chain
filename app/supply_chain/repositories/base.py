from typing import Any, LiteralString, Sequence

import psycopg
from psycopg.rows import class_row


class Repository:
    # Запис лише через CALL scm.sp_*, читання з scm.v_* і scm.fn_*. Транзакцією керує UnitOfWork.
    def __init__(self, conn: psycopg.Connection) -> None:
        self._conn = conn

    def _execute(self, sql: LiteralString, params: Sequence[Any] = ()) -> None:
        with self._conn.cursor() as cur:
            cur.execute(sql, params)

    # CALL з INOUT-параметром повертає один рядок
    def _scalar(self, sql: LiteralString, params: Sequence[Any] = ()) -> Any:
        with self._conn.cursor() as cur:
            cur.execute(sql, params)
            row = cur.fetchone()
            return None if row is None else row[0]

    def _query[T](self, sql: LiteralString, model: type[T], params: Sequence[Any] = ()) -> list[T]:
        with self._conn.cursor(row_factory=class_row(model)) as cur:
            cur.execute(sql, params)
            return cur.fetchall()

    def _query_one[T](self, sql: LiteralString, model: type[T], params: Sequence[Any] = ()) -> T | None:
        rows = self._query(sql, model, params)
        if len(rows) > 1:
            raise LookupError(f"Очікувався один рядок, отримано {len(rows)}")
        return rows[0] if rows else None
