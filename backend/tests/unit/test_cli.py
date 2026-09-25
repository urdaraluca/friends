import gzip
import io
import json
import sqlite3
from contextlib import closing
from datetime import UTC, datetime
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from friends_api import cli
from friends_api.core.config import AppEnv, Settings
from friends_api.main import create_app
from tests.conftest import FAST_ARGON2, sqlite_url


def _settings(tmp_path: Path, db_name: str = "app.db") -> Settings:
    return Settings(
        _env_file=None,
        app_env=AppEnv.TEST,
        database_url=sqlite_url(tmp_path / db_name),
        backup_dir=tmp_path / "backups",
        **FAST_ARGON2,
    )


def test_migrate_creates_the_database_without_a_backup(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    settings = _settings(tmp_path)

    assert cli.main(["migrate"], settings) == 0

    assert (tmp_path / "app.db").exists()
    assert not (tmp_path / "backups").exists()
    assert "up to date" in capsys.readouterr().out


def test_migrate_backs_up_before_applying_pending_migrations(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    conn = sqlite3.connect(tmp_path / "app.db")
    conn.execute("CREATE TABLE legacy (x)")
    conn.commit()
    conn.close()

    assert cli.main(["migrate"], settings) == 0

    backups = list((tmp_path / "backups").glob("pre-migrate-*.db.gz"))
    assert len(backups) == 1

    # Nothing pending now: no second backup.
    assert cli.main(["migrate"], settings) == 0
    assert len(list((tmp_path / "backups").glob("pre-migrate-*.db.gz"))) == 1


def _make_db(path: Path) -> None:
    conn = sqlite3.connect(path)
    conn.execute("CREATE TABLE t (x)")
    conn.execute("INSERT INTO t VALUES (42)")
    conn.commit()
    conn.close()


def test_backup_command_writes_a_gzip(tmp_path: Path) -> None:
    _make_db(tmp_path / "app.db")

    assert cli.main(["backup"], _settings(tmp_path)) == 0

    assert len(list((tmp_path / "backups").glob("friends-*.db.gz"))) == 1


def test_backup_is_verified_and_rotated(tmp_path: Path) -> None:
    _make_db(tmp_path / "app.db")

    for day in range(20, 25):
        cli.backup_database(
            tmp_path / "app.db",
            tmp_path / "backups",
            prefix="friends-",
            keep=3,
            now=datetime(2026, 9, day, tzinfo=UTC),
        )

    backups = sorted((tmp_path / "backups").glob("friends-*.db.gz"))
    assert [b.name for b in backups] == [
        "friends-20260922T000000Z.db.gz",
        "friends-20260923T000000Z.db.gz",
        "friends-20260924T000000Z.db.gz",
    ]
    restored = tmp_path / "restored.db"
    restored.write_bytes(gzip.decompress(backups[-1].read_bytes()))
    with closing(sqlite3.connect(restored)) as conn:
        assert conn.execute("SELECT x FROM t").fetchone() == (42,)


def test_backup_without_database_fails(tmp_path: Path) -> None:
    assert cli.main(["backup"], _settings(tmp_path, "missing.db")) == 1


def test_export_openapi_is_deterministic(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    first, second = tmp_path / "a.json", tmp_path / "b.json"

    assert cli.main(["export-openapi", "--output", str(first)], settings) == 0
    assert cli.main(["export-openapi", "--output", str(second)], settings) == 0

    assert first.read_bytes() == second.read_bytes()
    assert b"\r\n" not in first.read_bytes()
    schema = json.loads(first.read_text(encoding="utf-8"))
    assert schema["info"]["version"] == "1"
    assert "/api/v1/health" in schema["paths"]


def test_only_file_sqlite_urls_are_supported() -> None:
    with pytest.raises(SystemExit):
        cli.sqlite_path("sqlite:///:memory:")
    with pytest.raises(SystemExit):
        cli.sqlite_path("postgresql://localhost/friends")


def test_create_user_and_reset_password(
    settings: Settings, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setattr("sys.stdin", io.StringIO("first password!\n"))
    assert (
        cli.main(
            ["create-user", "--email", "Owner@Example.com", "--name", "Owner", "--password-stdin"],
            settings,
        )
        == 0
    )
    assert "Created user owner@example.com" in capsys.readouterr().out

    monkeypatch.setattr("sys.stdin", io.StringIO("second password!\n"))
    assert (
        cli.main(["reset-password", "--email", "owner@example.com", "--password-stdin"], settings)
        == 0
    )

    with TestClient(create_app(settings)) as client:
        old = client.post(
            "/api/v1/auth/login", json={"email": "owner@example.com", "password": "first password!"}
        )
        new = client.post(
            "/api/v1/auth/login",
            json={"email": "owner@example.com", "password": "second password!"},
        )
    assert old.status_code == 401
    assert new.status_code == 200


def test_create_user_rejects_duplicates_and_short_passwords(
    settings: Settings, monkeypatch: pytest.MonkeyPatch
) -> None:
    args = ["create-user", "--email", "a@example.com", "--name", "A", "--password-stdin"]
    monkeypatch.setattr("sys.stdin", io.StringIO("long enough password\n"))
    assert cli.main(args, settings) == 0

    monkeypatch.setattr("sys.stdin", io.StringIO("long enough password\n"))
    assert cli.main(args, settings) == 1

    monkeypatch.setattr("sys.stdin", io.StringIO("short\n"))
    assert cli.main([*args[:2], "b@example.com", *args[3:]], settings) == 1


def test_reset_password_for_unknown_email_fails(
    settings: Settings, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr("sys.stdin", io.StringIO("long enough password\n"))

    assert (
        cli.main(["reset-password", "--email", "x@example.com", "--password-stdin"], settings) == 1
    )
