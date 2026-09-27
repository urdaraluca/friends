"""Backup file names, shared by the ``backup``/``migrate`` commands and the metrics."""

from pathlib import Path

SCHEDULED_PREFIX = "friends-"
PRE_MIGRATE_PREFIX = "pre-migrate-"
PRE_MIGRATE_KEEP = 5


def scheduled_backups(backup_dir: Path) -> list[Path]:
    """The scheduled (``backup`` command) backups, oldest first; none if the directory can't
    be read."""
    try:
        return sorted(backup_dir.glob(f"{SCHEDULED_PREFIX}*.db.gz"))
    except OSError:
        return []
