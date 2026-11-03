from typing import Annotated

from fastapi import APIRouter, Depends, Query, status
from pydantic import BaseModel, StringConstraints

from friends_api.core.ratelimit import limit_by_ip
from friends_api.core.schemas import RequestModel
from friends_api.deps import AppSettings, CurrentUser, DbSession, PusherDep
from friends_api.features.emails import tokens
from friends_api.features.emails.tokens import NotificationKind
from friends_api.features.notifications import push, service

router = APIRouter(tags=["notifications"])


class Unsubscribed(BaseModel):
    kind: NotificationKind
    """The notifications that are now off (email and push)."""


class PushConfig(BaseModel):
    public_key: str | None
    """The VAPID ``applicationServerKey`` (base64url); null when push isn't set up."""


class PushKeys(RequestModel):
    p256dh: Annotated[str, StringConstraints(min_length=1, max_length=200)]
    auth: Annotated[str, StringConstraints(min_length=1, max_length=100)]


class PushSubscriptionWrite(RequestModel):
    """A browser's ``PushSubscription.toJSON()``, minus ``expirationTime``."""

    endpoint: Annotated[str, StringConstraints(min_length=1, max_length=1000)]
    keys: PushKeys


@router.post("/notifications/unsubscribe", dependencies=[Depends(limit_by_ip("email_links"))])
def unsubscribe(
    token: Annotated[str, Query(max_length=512)], db: DbSession, settings: AppSettings
) -> Unsubscribed:
    """Public: turns off one kind of notification with the token from an email's unsubscribe
    link. Mail apps call it too (RFC 8058 one-click: a form body, which is ignored)."""
    user_id, kind = tokens.read_unsubscribe_token(settings, token)
    service.unsubscribe(db, user_id, kind)
    return Unsubscribed(kind=kind)


@router.get("/push/config")
def get_push_config(_user: CurrentUser, pusher: PusherDep) -> PushConfig:
    return PushConfig(public_key=pusher.public_key)


@router.put("/me/push-subscription", status_code=status.HTTP_204_NO_CONTENT)
def save_push_subscription(body: PushSubscriptionWrite, db: DbSession, user: CurrentUser) -> None:
    """Turns push on for this browser (or refreshes its keys)."""
    push.save_subscription(
        db, user.id, endpoint=body.endpoint, p256dh=body.keys.p256dh, auth=body.keys.auth
    )


@router.delete("/me/push-subscription", status_code=status.HTTP_204_NO_CONTENT)
def delete_push_subscription(
    endpoint: Annotated[str, Query(max_length=1000)], db: DbSession, user: CurrentUser
) -> None:
    """Turns push off for this browser. Idempotent."""
    push.delete_subscription(db, user.id, endpoint)
