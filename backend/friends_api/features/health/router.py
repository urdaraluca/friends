from typing import Literal

from fastapi import APIRouter, Request
from pydantic import BaseModel

router = APIRouter(prefix="/health", tags=["health"])


class Health(BaseModel):
    status: Literal["ok"]
    version: str


@router.get("")
def get_health(request: Request) -> Health:
    return Health(status="ok", version=request.app.state.settings.app_version)
