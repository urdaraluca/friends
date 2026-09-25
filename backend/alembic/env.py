"""Alembic environment.

SQLite ALTERs are done in batch mode (copy table, drop, rename). With foreign keys ON,
DROP TABLE would fire ON DELETE CASCADE and delete child rows, so migrations run with
foreign keys OFF and verify integrity with PRAGMA foreign_key_check afterwards.
"""

from logging.config import fileConfig
from typing import Any

from alembic import context

from friends_api import db_models
from friends_api.core.config import get_settings
from friends_api.core.db import UTCDateTime, create_db_engine

config = context.config
if config.config_file_name is not None and config.attributes.get("configure_logger", True):
    fileConfig(config.config_file_name, disable_existing_loggers=False)

target_metadata = db_models.Base.metadata


def render_item(type_: str, obj: Any, autogen_context: Any) -> str | bool:
    """Renders our custom column types with an import instead of a module path."""
    if type_ == "type" and isinstance(obj, UTCDateTime):
        autogen_context.imports.add("from friends_api.core.db import UTCDateTime")
        return "UTCDateTime()"
    return False


def _database_url() -> str:
    url = config.get_main_option("sqlalchemy.url")
    return url or get_settings().database_url


def run_migrations_offline() -> None:
    context.configure(
        url=_database_url(),
        target_metadata=target_metadata,
        literal_binds=True,
        render_as_batch=True,
        render_item=render_item,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    engine = create_db_engine(_database_url(), foreign_keys=False)
    try:
        with engine.connect() as connection:
            context.configure(
                connection=connection,
                target_metadata=target_metadata,
                render_as_batch=True,
                render_item=render_item,
                compare_type=True,
            )
            with context.begin_transaction():
                context.run_migrations()
            violations = connection.exec_driver_sql("PRAGMA foreign_key_check").fetchall()
            if violations:
                raise RuntimeError(f"Foreign key violations after migration: {violations[:10]}")
    finally:
        engine.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
