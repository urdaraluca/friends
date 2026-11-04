"""Browser push subscriptions (contract section 18.6)."""

import uuid
from urllib.parse import urlsplit

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from friends_api.core.errors import FieldError, Unprocessable
from friends_api.core.webpush import b64url_decode
from friends_api.features.notifications.models import PushSubscription

PUSH_SERVICE_HOSTS = (
    "fcm.googleapis.com",
    "android.googleapis.com",
    "push.services.mozilla.com",
    "push.apple.com",
    "notify.windows.com",
)
"""The server only ever POSTs to these push services (and their subdomains): an endpoint is a
URL a client sends, so anything else could point the server at an internal address."""
MAX_SUBSCRIPTIONS = 20


def _invalid(field: str, message: str) -> Unprocessable:
    return Unprocessable(
        message, errors=[FieldError(field=field, message=message, type="value_error")]
    )


def check_endpoint(endpoint: str) -> None:
    parts = urlsplit(endpoint)
    host = (parts.hostname or "").lower()
    if parts.scheme != "https" or not any(
        host == allowed or host.endswith(f".{allowed}") for allowed in PUSH_SERVICE_HOSTS
    ):
        raise _invalid("body.endpoint", "Not a known browser push service.")


def check_keys(p256dh: str, auth: str) -> None:
    try:
        public, secret = b64url_decode(p256dh), b64url_decode(auth)
    except ValueError as exc:
        raise _invalid("body.keys", "Keys must be base64url.") from exc
    if len(public) != 65 or public[0] != 4:
        raise _invalid("body.keys.p256dh", "Not an uncompressed P-256 public key.")
    if len(secret) != 16:
        raise _invalid("body.keys.auth", "The auth secret must be 16 bytes.")


def save_subscription(
    db: Session, user_id: uuid.UUID, *, endpoint: str, p256dh: str, auth: str
) -> None:
    """Adds or refreshes this browser's subscription for ``user_id`` (an endpoint another
    account had on this browser moves to this one). Keeps the newest 20 per user."""
    check_endpoint(endpoint)
    check_keys(p256dh, auth)
    row = db.scalar(select(PushSubscription).where(PushSubscription.endpoint == endpoint))
    if row is None:
        db.add(PushSubscription(user_id=user_id, endpoint=endpoint, p256dh=p256dh, auth=auth))
    else:
        row.user_id, row.p256dh, row.auth = user_id, p256dh, auth
    db.flush()
    keep = (
        select(PushSubscription.id)
        .where(PushSubscription.user_id == user_id)
        .order_by(PushSubscription.created_at.desc())
        .limit(MAX_SUBSCRIPTIONS)
    )
    db.execute(
        delete(PushSubscription).where(
            PushSubscription.user_id == user_id, PushSubscription.id.not_in(keep)
        )
    )
    db.commit()


def delete_subscription(db: Session, user_id: uuid.UUID, endpoint: str) -> None:
    db.execute(
        delete(PushSubscription).where(
            PushSubscription.user_id == user_id, PushSubscription.endpoint == endpoint
        )
    )
    db.commit()
