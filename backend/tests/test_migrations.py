from pathlib import Path

from alembic import command
from alembic.config import Config

from friends_api.cli import alembic_config
from tests.conftest import sqlite_url


def _config(path: Path) -> Config:
    config = alembic_config(sqlite_url(path))
    config.attributes["configure_logger"] = False
    return config


def test_migrations_upgrade_downgrade_upgrade(tmp_path: Path) -> None:
    config = _config(tmp_path / "m.db")

    command.upgrade(config, "head")
    command.downgrade(config, "base")
    command.upgrade(config, "head")


def test_models_match_migrations(tmp_path: Path) -> None:
    """Fails when a model changed without a migration (alembic check)."""
    config = _config(tmp_path / "c.db")
    command.upgrade(config, "head")

    command.check(config)
