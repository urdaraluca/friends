"""Accounts and sessions.

A *session* is a refresh-token family: created at login/registration, rotated on every
refresh. Presenting an already-used token revokes the whole family (it may have been
stolen), except within a short grace window when the successor was never used: that is
a client that lost the refresh response, and it gets a fresh successor instead.
"""

import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta

from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from friends_api.core.config import Settings
from friends_api.core.db import utcnow
from friends_api.core.errors import AuthError, Conflict, FieldError, Unprocessable
from friends_api.core.security import (
    Passwords,
    create_access_token,
    hash_refresh_token,
    new_refresh_token,
)
from friends_api.features.auth.models import RefreshToken, User
from friends_api.features.auth.schemas import TokenPair
from friends_api.features.users.schemas import is_valid_timezone


@dataclass(frozen=True, slots=True)
class AuthContext:
    settings: Settings
    passwords: Passwords


def normalize_email(email: str) -> str:
    return email.strip().lower()


def _check_password_rules(password: str, email: str) -> None:
    if password.strip().lower() == email:
        raise Unprocessable("Password must not be your email address.", code="weak_password")


def _issue_tokens(
    db: Session,
    ctx: AuthContext,
    user: User,
    *,
    family_id: uuid.UUID,
    session_started_at: datetime,
    device_label: str | None,
) -> tuple[TokenPair, RefreshToken]:
    now = utcnow()
    session_cap = session_started_at + timedelta(days=ctx.settings.refresh_session_max_days)
    expires_at = min(now + timedelta(days=ctx.settings.refresh_token_ttl_days), session_cap)
    if expires_at <= now:  # the session reached its absolute cap
        raise _refresh_invalid()
    token, token_hash = new_refresh_token()
    row = RefreshToken(
        user_id=user.id,
        family_id=family_id,
        token_hash=token_hash,
        session_started_at=session_started_at,
        expires_at=expires_at,
        device_label=device_label,
    )
    db.add(row)
    db.flush()
    access_token, access_ttl = create_access_token(
        ctx.settings, user_id=user.id, session_id=family_id, token_version=user.token_version
    )
    pair = TokenPair(
        access_token=access_token,
        refresh_token=token,
        access_expires_in=access_ttl,
        refresh_expires_at=expires_at,
    )
    return pair, row


def start_session(db: Session, ctx: AuthContext, user: User, device_label: str | None) -> TokenPair:
    pair, _ = _issue_tokens(
        db,
        ctx,
        user,
        family_id=uuid.uuid7(),
        session_started_at=utcnow(),
        device_label=device_label,
    )
    return pair


def create_user(
    db: Session,
    ctx: AuthContext,
    *,
    email: str,
    password: str,
    display_name: str,
    timezone: str | None = None,
) -> User:
    """Creates the account (flushes, does not commit)."""
    email = normalize_email(email)
    _check_password_rules(password, email)
    if db.scalar(select(User.id).where(User.email == email)) is not None:
        raise Conflict("An account with this email already exists.", code="email_taken")
    user = User(
        email=email,
        password_hash=ctx.passwords.hash(password),
        display_name=display_name,
        timezone=timezone if timezone and is_valid_timezone(timezone) else "UTC",
    )
    db.add(user)
    try:
        db.flush()
    except IntegrityError as exc:  # concurrent registration with the same email
        raise Conflict("An account with this email already exists.", code="email_taken") from exc
    return user


def authenticate(db: Session, ctx: AuthContext, email: str, password: str) -> User:
    user = db.scalar(
        select(User).where(User.email == normalize_email(email), User.deleted_at.is_(None))
    )
    if not ctx.passwords.verify(user.password_hash if user else None, password) or user is None:
        raise AuthError("Wrong email or password.", code="invalid_credentials")
    assert user.password_hash is not None  # noqa: S101 - verify() is False for null hashes
    if ctx.passwords.needs_rehash(user.password_hash):
        user.password_hash = ctx.passwords.hash(password)
    user.last_login_at = utcnow()
    return user


def refresh_session(db: Session, ctx: AuthContext, presented: str) -> TokenPair:
    """Rotates a refresh token (contract section 4.5)."""
    now = utcnow()
    row = db.scalar(
        select(RefreshToken).where(RefreshToken.token_hash == hash_refresh_token(presented))
    )
    user = db.get(User, row.user_id) if row is not None else None
    if row is None or row.revoked_at is not None or user is None or not user.is_active:
        raise _refresh_invalid()

    if row.used_at is not None:
        successor = db.get(RefreshToken, row.replaced_by_id) if row.replaced_by_id else None
        grace = timedelta(seconds=ctx.settings.refresh_reuse_grace_seconds)
        if (
            successor is None
            or now - row.used_at > grace
            or successor.used_at is not None
            or successor.revoked_at is not None
        ):
            _revoke_family(db, row.family_id, now)
            db.commit()
            raise AuthError("Session revoked, please sign in again.", code="refresh_reuse_detected")
        # The client lost the response carrying `successor`: replace it.
        successor.revoked_at = now
    elif row.expires_at <= now:
        raise _refresh_invalid()

    pair, new_row = _issue_tokens(
        db,
        ctx,
        user,
        family_id=row.family_id,
        session_started_at=row.session_started_at,
        device_label=row.device_label,
    )
    row.used_at = row.used_at or now
    row.replaced_by_id = new_row.id
    db.commit()
    return pair


def _refresh_invalid() -> AuthError:
    return AuthError("Session expired, please sign in again.", code="refresh_invalid")


def _revoke_family(db: Session, family_id: uuid.UUID, now: datetime) -> None:
    db.execute(
        update(RefreshToken)
        .where(RefreshToken.family_id == family_id, RefreshToken.revoked_at.is_(None))
        .values(revoked_at=now)
    )


def revoke_all_sessions(db: Session, user: User) -> None:
    db.execute(
        update(RefreshToken)
        .where(RefreshToken.user_id == user.id, RefreshToken.revoked_at.is_(None))
        .values(revoked_at=utcnow())
    )


def logout(db: Session, presented: str) -> None:
    row = db.scalar(
        select(RefreshToken).where(RefreshToken.token_hash == hash_refresh_token(presented))
    )
    if row is not None:
        _revoke_family(db, row.family_id, utcnow())
        db.commit()


def logout_everywhere(db: Session, user: User) -> None:
    user.token_version += 1
    revoke_all_sessions(db, user)
    db.commit()


def check_current_password(ctx: AuthContext, user: User, password: str, field: str) -> None:
    if not ctx.passwords.verify(user.password_hash, password):
        raise Unprocessable(
            "The password is wrong.",
            code="wrong_password",
            errors=[FieldError(field=field, message="Wrong password.", type="wrong_password")],
        )


def change_password(
    db: Session,
    ctx: AuthContext,
    user: User,
    *,
    current_password: str,
    new_password: str,
    session_id: uuid.UUID,
) -> TokenPair:
    """Changes the password and signs out every session, then starts a new one for the caller.

    The caller keeps being signed in (same session start and device); every other device is out.
    """
    check_current_password(ctx, user, current_password, "current_password")
    _check_password_rules(new_password, user.email)
    current = db.scalar(
        select(RefreshToken)
        .where(RefreshToken.family_id == session_id)
        .order_by(RefreshToken.created_at.desc())
        .limit(1)
    )
    user.password_hash = ctx.passwords.hash(new_password)
    user.token_version += 1
    revoke_all_sessions(db, user)
    pair, _ = _issue_tokens(
        db,
        ctx,
        user,
        family_id=uuid.uuid7(),
        session_started_at=current.session_started_at if current else utcnow(),
        device_label=current.device_label if current else None,
    )
    db.commit()
    return pair
