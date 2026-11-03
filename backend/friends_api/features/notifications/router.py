from typing import Annotated

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel

from friends_api.core.ratelimit import limit_by_ip
from friends_api.deps import AppSettings, DbSession
from friends_api.features.emails import tokens
from friends_api.features.emails.tokens import NotificationKind
from friends_api.features.notifications import service

router = APIRouter(tags=["notifications"])


class Unsubscribed(BaseModel):
    kind: NotificationKind
    """The notification emails that are now off."""


@router.post("/notifications/unsubscribe", dependencies=[Depends(limit_by_ip("email_links"))])
def unsubscribe(
    token: Annotated[str, Query(max_length=512)], db: DbSession, settings: AppSettings
) -> Unsubscribed:
    """Public: turns off one kind of notification email with the token from its unsubscribe
    link. Mail apps call it too (RFC 8058 one-click: a form body, which is ignored)."""
    user_id, kind = tokens.read_unsubscribe_token(settings, token)
    service.unsubscribe(db, user_id, kind)
    return Unsubscribed(kind=kind)
