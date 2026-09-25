"""Database engine, sessions and shared column types.

SQLite specifics that matter:
- Every connection gets WAL, foreign keys, a busy timeout and NORMAL sync.
- pysqlite's own transaction handling is disabled and we emit BEGIN ourselves, so
  write sessions can use ``BEGIN IMMEDIATE`` (take the write lock up front instead of
  failing with SQLITE_BUSY when a read transaction later tries to write).
"""

import uuid
from datetime import UTC, datetime
from enum import StrEnum
from typing import Any

from sqlalchemy import DateTime, Dialect, Engine, MetaData, Uuid, create_engine, event
from sqlalchemy import Enum as SAEnum
from sqlalchemy.engine import Connection
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker
from sqlalchemy.types import TypeDecorator

NAMING_CONVENTION = {
    "ix": "ix_%(column_0_label)s",
    "uq": "uq_%(table_name)s_%(column_0_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}


def utcnow() -> datetime:
    return datetime.now(UTC)


class UTCDateTime(TypeDecorator[datetime]):
    """Stores timezone-aware datetimes as naive UTC; always returns aware UTC datetimes."""

    impl = DateTime
    cache_ok = True

    def process_bind_param(self, value: datetime | None, dialect: Dialect) -> datetime | None:
        if value is None:
            return None
        if value.tzinfo is None:
            raise ValueError("naive datetime; use timezone-aware datetimes (UTC)")
        return value.astimezone(UTC).replace(tzinfo=None)

    def process_result_value(self, value: datetime | None, dialect: Dialect) -> datetime | None:
        if value is None:
            return None
        return value.replace(tzinfo=UTC)


class Base(DeclarativeBase):
    metadata = MetaData(naming_convention=NAMING_CONVENTION)
    type_annotation_map = {datetime: UTCDateTime(), uuid.UUID: Uuid()}  # noqa: RUF012


class IdMixin:
    """Time-ordered UUIDv7 primary key."""

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid7)


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(default=utcnow, onupdate=utcnow)


def create_db_engine(
    url: str, *, foreign_keys: bool = True, busy_timeout_ms: int = 5000, echo: bool = False
) -> Engine:
    engine = create_engine(url, echo=echo)

    @event.listens_for(engine, "connect")
    def _on_connect(dbapi_connection: Any, _record: Any) -> None:
        # Hand transaction control to SQLAlchemy's "begin" event below.
        dbapi_connection.isolation_level = None
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA journal_mode=WAL")
        cursor.execute("PRAGMA synchronous=NORMAL")
        cursor.execute(f"PRAGMA foreign_keys={'ON' if foreign_keys else 'OFF'}")
        cursor.execute(f"PRAGMA busy_timeout={int(busy_timeout_ms)}")
        cursor.execute("PRAGMA temp_store=MEMORY")
        cursor.close()

    @event.listens_for(engine, "begin")
    def _on_begin(connection: Connection) -> None:
        mode = connection.get_execution_options().get("sqlite_begin", "DEFERRED")
        connection.exec_driver_sql(f"BEGIN {mode}")

    return engine


def create_session_factories(engine: Engine) -> tuple[sessionmaker[Any], sessionmaker[Any]]:
    """Returns (read, write) session factories sharing one connection pool."""
    read = sessionmaker(engine, expire_on_commit=False)
    write = sessionmaker(engine.execution_options(sqlite_begin="IMMEDIATE"), expire_on_commit=False)
    return read, write


def str_enum[E: StrEnum](enum_cls: type[E], length: int) -> SAEnum:
    """A StrEnum stored as its value in a VARCHAR, without a CHECK constraint (new values need
    no table rebuild on SQLite)."""
    return SAEnum(
        enum_cls,
        native_enum=False,
        create_constraint=False,
        length=length,
        values_callable=lambda members: [member.value for member in members],
    )
