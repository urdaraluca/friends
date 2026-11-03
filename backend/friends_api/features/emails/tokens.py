"""Single-use email links (contract section 18.2) and unsubscribe tokens (section 18.4)."""

import secrets
import uuid
from datetime import timedelta
from enum import StrEnum

import jwt
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from friends_api.core.config import Settings
from friends_api.core.db import utcnow
from friends_api.core.errors import FieldError, Unprocessable
from friends_api.core.security import JWT_ALGORITHM, JWT_ISSUER, hash_refresh_token
from friends_api.features.auth.models import EmailToken, EmailTokenPurpose, User

TOKEN_TTL = {
    EmailTokenPurpose.VERIFY_EMAIL: timedelta(days=7),
    EmailTokenPurpose.RESET_PASSWORD: timedelta(hours=1),
}
UNSUBSCRIBE_AUDIENCE = "friends-unsubscribe"


class NotificationKind(StrEnum):
    POLLS = "polls"
    WHEEL = "wheel"
    REMINDERS = "reminders"


def issue_token(db: Session, user: User, purpose: EmailTokenPurpose) -> str:
    """A new link token for ``user``; their earlier unused ones for ``purpose`` stop working.
    Flushes, does not commit."""
    db.execute(
        delete(EmailToken).where(
            EmailToken.user_id == user.id,
            EmailToken.purpose == purpose,
            EmailToken.used_at.is_(None),
        )
    )
    token = secrets.token_urlsafe(32)
    db.add(
        EmailToken(
            user_id=user.id,
            purpose=purpose,
            token_hash=hash_refresh_token(token),
            email=user.email,
            expires_at=utcnow() + TOKEN_TTL[purpose],
        )
    )
    db.flush()
    return token


def invalid_token() -> Unprocessable:
    message = "This link is invalid or has expired."
    return Unprocessable(
        message,
        code="invalid_token",
        errors=[FieldError(field="token", message=message, type="invalid_token")],
    )


def consume_token(db: Session, token: str, purpose: EmailTokenPurpose) -> User:
    """The user ``token`` was issued to, marking it used. Unknown, used, expired, for another
    purpose, for an address the user no longer has, or for a deleted user: 422 ``invalid_token``.
    """
    row = db.scalar(select(EmailToken).where(EmailToken.token_hash == hash_refresh_token(token)))
    user = db.get(User, row.user_id) if row is not None else None
    if (
        row is None
        or user is None
        or row.purpose != purpose
        or row.used_at is not None
        or row.expires_at <= utcnow()
        or row.email != user.email
        or not user.is_active
    ):
        raise invalid_token()
    row.used_at = utcnow()
    return user


def mark_verified(user: User) -> None:
    if user.email_verified_at is None:
        user.email_verified_at = utcnow()


def unsubscribe_token(settings: Settings, user_id: uuid.UUID, kind: NotificationKind) -> str:
    """Signed, without expiry: an unsubscribe link must keep working in old emails."""
    payload = {
        "sub": str(user_id),
        "kind": kind.value,
        "iss": JWT_ISSUER,
        "aud": UNSUBSCRIBE_AUDIENCE,
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=JWT_ALGORITHM)


def read_unsubscribe_token(settings: Settings, token: str) -> tuple[uuid.UUID, NotificationKind]:
    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret,
            algorithms=[JWT_ALGORITHM],
            audience=UNSUBSCRIBE_AUDIENCE,
            issuer=JWT_ISSUER,
            options={"require": ["sub", "kind"]},
        )
        return uuid.UUID(payload["sub"]), NotificationKind(payload["kind"])
    except (jwt.InvalidTokenError, ValueError) as exc:
        raise invalid_token() from exc
