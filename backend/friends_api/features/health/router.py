import logging
from typing import Literal

from fastapi import APIRouter, Response
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from friends_api.deps import AppSettings, DbSession

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/health", tags=["health"])


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
