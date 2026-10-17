import json
import os
from dataclasses import dataclass
from pathlib import Path

CONFIG_PATH = Path(__file__).resolve().parent.parent / "config.json"


@dataclass(frozen=True, slots=True)
class DemoUsers:
    sales: str
    store: str
    manager: str


@dataclass(frozen=True, slots=True)
class Settings:
    connection: str
    users: DemoUsers


def load_settings(argv: list[str]) -> Settings:
    # пріоритет: аргумент командного рядка, SCM_CONNECTION, config.json
    raw = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    connection = (argv[0] if argv else None) or os.environ.get("SCM_CONNECTION") or raw["connection"]
    return Settings(connection=connection, users=DemoUsers(**raw["users"]))
