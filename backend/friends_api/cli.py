"""Operational commands: ``python -m friends_api.cli <command>``.

- ``migrate``: back up the database if migrations are pending, then ``alembic upgrade head``.
- ``backup``: consistent online backup (safe while the app is running), gzip, rotate.
- ``export-openapi``: write the OpenAPI schema used to generate the Dart client.
- ``create-user`` / ``reset-password``: account administration (there is no email sending).
- ``seed-demo``: demo users, a group and its data for development (refused in prod).
"""

import argparse
import getpass
import gzip
import json
import shutil
import sqlite3
import sys
import tempfile
from collections.abc import Sequence
from datetime import UTC, datetime
from pathlib import Path

from alembic import command
from alembic.config import Config
from alembic.runtime.migration import MigrationContext
from alembic.script import ScriptDirectory
from sqlalchemy import delete, select
from sqlalchemy.engine import make_url

from friends_api.core.config import AppEnv, Settings, get_settings
from friends_api.core.db import create_db_engine, create_session_factories
from friends_api.core.errors import AppError
from friends_api.core.security import Passwords
from friends_api.demo.base import demo_users_exist
from friends_api.demo.context import DEMO_EMAILS, DEMO_PASSWORD
from friends_api.demo.runner import seed_demo
from friends_api.features.auth import service as auth_service
from friends_api.features.auth.models import RefreshToken, User
from friends_api.features.auth.service import AuthContext
from friends_api.main import create_app

BACKEND_DIR = Path(__file__).resolve().parent.parent
DEFAULT_OPENAPI_PATH = BACKEND_DIR / "openapi.json"
SCHEDULED_PREFIX = "friends-"
PRE_MIGRATE_PREFIX = "pre-migrate-"
PRE_MIGRATE_KEEP = 10


def sqlite_path(database_url: str) -> Path:
    url = make_url(database_url)
    if url.get_backend_name() != "sqlite" or not url.database or url.database == ":memory:":
        raise SystemExit(f"Only file-based SQLite databases are supported, got {database_url!r}")
    return Path(url.database)


def alembic_config(database_url: str) -> Config:
    config = Config(str(BACKEND_DIR / "alembic.ini"))
    config.set_main_option("script_location", str(BACKEND_DIR / "alembic"))
    config.set_main_option("sqlalchemy.url", database_url)
    return config


def pending_migrations(database_url: str) -> bool:
    script = ScriptDirectory.from_config(alembic_config(database_url))
    engine = create_db_engine(database_url)
    try:
        with engine.connect() as connection:
            current = set(MigrationContext.configure(connection).get_current_heads())
    finally:
        engine.dispose()
    return current != set(script.get_heads())


def backup_database(
    db_path: Path, backup_dir: Path, *, prefix: str, keep: int, now: datetime | None = None
) -> Path:
    """Copies the live database with SQLite's online backup API, verifies it, gzips it."""
    backup_dir.mkdir(parents=True, exist_ok=True)
    stamp = (now or datetime.now(UTC)).strftime("%Y%m%dT%H%M%SZ")
    target = backup_dir / f"{prefix}{stamp}.db.gz"

    with tempfile.TemporaryDirectory(dir=backup_dir) as tmp:
        snapshot = Path(tmp) / "snapshot.db"
        source = sqlite3.connect(db_path)
        destination = sqlite3.connect(snapshot)
        try:
            source.backup(destination)
            (result,) = destination.execute("PRAGMA integrity_check").fetchone()
            if result != "ok":
                raise RuntimeError(f"Backup failed integrity_check: {result}")
        finally:
            destination.close()
            source.close()
        with snapshot.open("rb") as raw, gzip.open(target, "wb") as compressed:
            shutil.copyfileobj(raw, compressed)

    backups = sorted(backup_dir.glob(f"{prefix}*.db.gz"))
    for old in backups[: max(0, len(backups) - keep)]:
        old.unlink()
    return target


def cmd_migrate(settings: Settings, _args: argparse.Namespace) -> int:
    db_path = sqlite_path(settings.database_url)
    db_path.parent.mkdir(parents=True, exist_ok=True)
    if (
        db_path.exists()
        and db_path.stat().st_size > 0
        and pending_migrations(settings.database_url)
    ):
        backup = backup_database(
            db_path, settings.backup_dir, prefix=PRE_MIGRATE_PREFIX, keep=PRE_MIGRATE_KEEP
        )
        print(f"Backed up database to {backup}")
    command.upgrade(alembic_config(settings.database_url), "head")
    print("Database is up to date.")
    return 0


def cmd_backup(settings: Settings, args: argparse.Namespace) -> int:
    db_path = sqlite_path(settings.database_url)
    if not db_path.exists():
        print(f"No database at {db_path}", file=sys.stderr)
        return 1
    backup_dir = Path(args.dir) if args.dir else settings.backup_dir
    keep = args.keep if args.keep is not None else settings.backup_keep
    target = backup_database(db_path, backup_dir, prefix=SCHEDULED_PREFIX, keep=keep)
    print(f"Backup written to {target}")
    return 0


def cmd_export_openapi(settings: Settings, args: argparse.Namespace) -> int:
    app = create_app(settings.model_copy(update={"docs_enabled": True}))
    output = Path(args.path) if args.path else DEFAULT_OPENAPI_PATH
    schema = json.dumps(app.openapi(), indent=2, ensure_ascii=False) + "\n"
    output.write_text(schema, encoding="utf-8", newline="\n")
    print(f"OpenAPI schema written to {output}")
    return 0


def _read_password(args: argparse.Namespace) -> str:
    if args.password_stdin:
        return sys.stdin.readline().rstrip("\r\n")
    password = getpass.getpass("Password: ")
    if password != getpass.getpass("Repeat password: "):
        raise SystemExit("Passwords do not match.")
    return password


def _password_problem(password: str) -> str | None:
    if not 10 <= len(password) <= 128:
        return "Password must be 10-128 characters."
    return None


def cmd_create_user(settings: Settings, args: argparse.Namespace) -> int:
    password = _read_password(args)
    if problem := _password_problem(password):
        print(problem, file=sys.stderr)
        return 1
    ctx = AuthContext(settings=settings, passwords=Passwords(settings))
    engine = create_db_engine(settings.database_url)
    _, write = create_session_factories(engine)
    try:
        with write() as db:
            user = auth_service.create_user(
                db, ctx, email=args.email, password=password, display_name=args.display_name
            )
            db.commit()
            print(f"Created user {user.email} ({user.id})")
    except AppError as exc:
        print(exc.detail or exc.code, file=sys.stderr)
        return 1
    finally:
        engine.dispose()
    return 0


def cmd_reset_password(settings: Settings, args: argparse.Namespace) -> int:
    password = _read_password(args)
    if problem := _password_problem(password):
        print(problem, file=sys.stderr)
        return 1
    passwords = Passwords(settings)
    engine = create_db_engine(settings.database_url)
    _, write = create_session_factories(engine)
    try:
        with write() as db:
            email = auth_service.normalize_email(args.email)
            user = db.scalar(select(User).where(User.email == email))
            if user is None or not user.is_active:
                print(f"No active user with email {args.email}", file=sys.stderr)
                return 1
            user.password_hash = passwords.hash(password)
            user.token_version += 1
            db.execute(delete(RefreshToken).where(RefreshToken.user_id == user.id))
            db.commit()
            print(f"Password reset for {user.email}; all their sessions were signed out.")
    finally:
        engine.dispose()
    return 0


def cmd_seed_demo(settings: Settings, _args: argparse.Namespace) -> int:
    if settings.app_env is AppEnv.PROD:
        print("seed-demo is disabled when APP_ENV=prod.", file=sys.stderr)
        return 2
    ctx = AuthContext(settings=settings, passwords=Passwords(settings))
    engine = create_db_engine(settings.database_url)
    _, write = create_session_factories(engine)
    try:
        with write() as db:
            if demo_users_exist(db):
                print("The demo users already exist; nothing was changed.", file=sys.stderr)
                return 1
            demo = seed_demo(db, ctx)
            db.commit()
            summary = (
                f"Created group '{demo.group.name}' with {len(demo.categories)} categories "
                f"and {len(demo.activities)} activities."
            )
    finally:
        engine.dispose()
    print(summary)
    print(f"Demo users: {', '.join(DEMO_EMAILS)}")
    print(f"Password: {DEMO_PASSWORD}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="python -m friends_api.cli")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("migrate", help="back up if needed, then apply migrations")

    backup = sub.add_parser("backup", help="online backup of the SQLite database")
    backup.add_argument("--keep", type=int, help="scheduled backups to keep (default: BACKUP_KEEP)")
    backup.add_argument("--dir", help="backup directory (default: BACKUP_DIR)")

    export = sub.add_parser("export-openapi", help="write the OpenAPI schema")
    export.add_argument("path", nargs="?", help=f"output path (default: {DEFAULT_OPENAPI_PATH})")

    create = sub.add_parser("create-user", help="create an account (e.g. the very first one)")
    create.add_argument("--email", required=True)
    create.add_argument("--display-name", required=True)
    create.add_argument(
        "--password-stdin", action="store_true", help="read the password from stdin"
    )

    reset = sub.add_parser("reset-password", help="set a new password and sign out all sessions")
    reset.add_argument("email")
    reset.add_argument("--password-stdin", action="store_true", help="read the password from stdin")

    sub.add_parser("seed-demo", help="create demo users and a group full of data (not in prod)")
    return parser


COMMANDS = {
    "migrate": cmd_migrate,
    "backup": cmd_backup,
    "export-openapi": cmd_export_openapi,
    "create-user": cmd_create_user,
    "reset-password": cmd_reset_password,
    "seed-demo": cmd_seed_demo,
}


def main(argv: Sequence[str] | None = None, settings: Settings | None = None) -> int:
    args = build_parser().parse_args(argv)
    return COMMANDS[args.command](settings or get_settings(), args)


if __name__ == "__main__":
    raise SystemExit(main())
