from ..models import AppUser
from .base import Repository


class UserRepository(Repository):
    _SELECT = "SELECT id, username, role, employee_id, employee_name FROM scm.v_app_user"

    def get_by_username(self, username: str) -> AppUser | None:
        return self._query_one(self._SELECT + " WHERE username = %s", AppUser, (username,))
