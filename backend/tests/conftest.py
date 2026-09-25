import shutil
from collections.abc import Iterator
from pathlib import Path
from typing import Any

import pytest
from alembic import command
from fastapi import FastAPI
from fastapi.testclient import TestClient

from friends_api.cli import alembic_config
from friends_api.core.config import AppEnv, RegistrationMode, Settings
from friends_api.main import create_app

# Cheap hashing parameters: the production ones cost ~64 MiB and a few hundred ms per hash.
FAST_ARGON2: dict[str, Any] = {
    "argon2_time_cost": 1,
    "argon2_memory_kib": 8,
    "argon2_parallelism": 1,
}


def sqlite_url(path: Path) -> str:
    return f"sqlite:///{path.as_posix()}"


@pytest.fixture(scope="session")
def migrated_template(tmp_path_factory: pytest.TempPathFactory) -> Path:
    """A database migrated to head once per session; each test gets its own copy."""
    path = tmp_path_factory.mktemp("template") / "template.db"
    config = alembic_config(sqlite_url(path))
    config.attributes["configure_logger"] = False
    command.upgrade(config, "head")
    return path


@pytest.fixture
def db_path(tmp_path: Path, migrated_template: Path) -> Path:
    path = tmp_path / "test.db"
    shutil.copyfile(migrated_template, path)
    return path


@pytest.fixture
def settings(db_path: Path, tmp_path: Path) -> Settings:
    return Settings(
        _env_file=None,
        app_env=AppEnv.TEST,
        app_version="test",
        database_url=sqlite_url(db_path),
        backup_dir=tmp_path / "backups",
        registration_mode=RegistrationMode.OPEN,
        rate_limit_enabled=False,
        **FAST_ARGON2,
    )


@pytest.fixture
def app(settings: Settings) -> FastAPI:
    return create_app(settings)


@pytest.fixture
def client(app: FastAPI) -> Iterator[TestClient]:
    with TestClient(app) as test_client:
        yield test_client
