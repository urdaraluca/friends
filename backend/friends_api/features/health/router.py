import hmac
import logging
from typing import Literal

from fastapi import APIRouter, Request, Response
from pydantic import BaseModel
from sqlalchemy import func, select, text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from friends_api.core.backups import scheduled_backups
from friends_api.core.config import Settings
from friends_api.core.errors import AuthError, NotFound
from friends_api.core.metrics import CONTENT_TYPE, RequestMetrics, gauge
from friends_api.deps import AppSettings, DbSession
from friends_api.features.activities.models import Activity
from friends_api.features.auth.models import User
from friends_api.features.events.models import Event
from friends_api.features.groups.models import Group

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/health", tags=["health"])
metrics_router = APIRouter(tags=["health"])


class Health(BaseModel):
    status: Literal["ok", "degraded"]
    version: str
    db: Literal["ok", "error"]


@router.get("", responses={503: {"model": Health}})
def get_health(db: DbSession, settings: AppSettings, response: Response) -> Health:
    try:
        db.execute(text("SELECT 1"))
    except SQLAlchemyError:
        logger.exception("Health check: database unavailable")
        response.status_code = 503
        return Health(status="degraded", version=settings.app_version, db="error")
    return Health(status="ok", version=settings.app_version, db="ok")


def _database_lines(db: Session) -> list[str]:
    try:
        counts = {
            "users": db.scalar(
                select(func.count()).select_from(User).where(User.deleted_at.is_(None))
            ),
            "groups": db.scalar(select(func.count()).select_from(Group)),
            "activities": db.scalar(select(func.count()).select_from(Activity)),
            "events": db.scalar(select(func.count()).select_from(Event)),
        }
    except SQLAlchemyError:
        logger.exception("Metrics: database unavailable")
        return gauge("friends_db_up", "Whether the database answers.", [({}, 0)])
    lines = gauge("friends_db_up", "Whether the database answers.", [({}, 1)])
    lines += gauge(
        "friends_rows",
        "Rows by table (users without deleted accounts).",
        [({"table": table}, count or 0) for table, count in counts.items()],
    )
    return lines


def _backup_lines(settings: Settings) -> list[str]:
    backups = scheduled_backups(settings.backup_dir)
    lines = gauge(
        "friends_backups",
        "Scheduled backups kept in BACKUP_DIR.",
        [({}, len(backups))],
    )
    newest = None
    for backup in reversed(backups):
        try:
            newest = backup.stat().st_mtime
        except OSError:
            continue
        break
    if newest is not None:
        lines += gauge(
            "friends_last_backup_timestamp_seconds",
            "When the newest scheduled backup was written (Unix time); alert when it is old.",
            [({}, newest)],
        )
    return lines


@metrics_router.get("/metrics", include_in_schema=False)
def get_metrics(request: Request, db: DbSession, settings: AppSettings) -> Response:
    """Prometheus text format, for a scraper with ``METRICS_TOKEN`` (contract section 1.13)."""
    token = settings.metrics_token
    if not token:
        raise NotFound("Metrics are off: set METRICS_TOKEN.")
    scheme, _, presented = request.headers.get("authorization", "").partition(" ")
    if scheme.lower() != "bearer" or not hmac.compare_digest(
        presented.strip().encode(), token.encode()
    ):
        raise AuthError("Send the metrics token as a Bearer token.")
    metrics: RequestMetrics = request.app.state.metrics
    lines = gauge(
        "friends_build_info",
        "The running build.",
        [({"version": settings.app_version, "git_sha": settings.git_sha}, 1)],
    )
    lines += _database_lines(db)
    lines += _backup_lines(settings)
    lines += metrics.lines()
    return Response("\n".join(lines) + "\n", media_type=CONTENT_TYPE)
