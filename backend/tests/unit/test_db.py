from datetime import UTC, datetime, timedelta, timezone
from pathlib import Path

import pytest
from sqlalchemy import Column, MetaData, Table, insert, select, text
from sqlalchemy.exc import StatementError

from friends_api.core.db import UTCDateTime, create_db_engine, create_session_factories
from tests.conftest import sqlite_url


def test_connections_get_the_sqlite_pragmas(tmp_path: Path) -> None:
    engine = create_db_engine(sqlite_url(tmp_path / "p.db"))
    with engine.connect() as conn:
        assert conn.exec_driver_sql("PRAGMA foreign_keys").scalar() == 1
        assert conn.exec_driver_sql("PRAGMA journal_mode").scalar() == "wal"
        assert conn.exec_driver_sql("PRAGMA busy_timeout").scalar() == 5000
        assert conn.exec_driver_sql("PRAGMA synchronous").scalar() == 1  # NORMAL
    engine.dispose()


def test_foreign_keys_can_be_disabled_for_migrations(tmp_path: Path) -> None:
    engine = create_db_engine(sqlite_url(tmp_path / "m.db"), foreign_keys=False)
    with engine.connect() as conn:
        assert conn.exec_driver_sql("PRAGMA foreign_keys").scalar() == 0
    engine.dispose()


def test_write_sessions_take_the_write_lock_immediately(tmp_path: Path) -> None:
    engine = create_db_engine(sqlite_url(tmp_path / "w.db"), busy_timeout_ms=50)
    read, write = create_session_factories(engine)
    with write() as writer, read() as reader:
        writer.execute(text("SELECT 1"))  # BEGIN IMMEDIATE: reserves the write lock
        reader.execute(text("SELECT 1"))  # readers are not blocked
        other = engine.execution_options(sqlite_begin="IMMEDIATE").connect()
        with pytest.raises(Exception, match="locked"):
            other.execute(text("SELECT 1"))
        other.close()
    engine.dispose()


def test_utc_datetime_round_trips_as_aware_utc(tmp_path: Path) -> None:
    engine = create_db_engine(sqlite_url(tmp_path / "t.db"))
    table = Table("t", MetaData(), Column("at", UTCDateTime()))
    table.create(engine)
    bucharest = timezone(timedelta(hours=3))
    with engine.begin() as conn:
        conn.execute(insert(table).values(at=datetime(2026, 10, 1, 19, 0, tzinfo=bucharest)))
        stored = conn.execute(select(table.c.at)).scalar_one()
        raw = conn.exec_driver_sql("SELECT at FROM t").scalar_one()

    assert stored == datetime(2026, 10, 1, 16, 0, tzinfo=UTC)
    assert stored.tzinfo is UTC
    assert raw.startswith("2026-10-01 16:00:00")
    engine.dispose()


def test_utc_datetime_rejects_naive_values(tmp_path: Path) -> None:
    engine = create_db_engine(sqlite_url(tmp_path / "n.db"))
    table = Table("t", MetaData(), Column("at", UTCDateTime()))
    table.create(engine)
    with engine.begin() as conn, pytest.raises(StatementError, match="naive datetime"):
        conn.execute(insert(table).values(at=datetime(2026, 10, 1, 19, 0)))  # noqa: DTZ001
    engine.dispose()
