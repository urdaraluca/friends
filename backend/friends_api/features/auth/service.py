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
from friends_api.core.errors import Conflict, Unauthenticated, ValidationFailed
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
        raise ValidationFailed("Password must not be your email address.", code="weak_password")


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
    session_cap = session_started_at + timedelta(days=ctx.settings.session_max_days)
    expires_at = min(now + timedelta(days=ctx.settings.refresh_token_ttl_days), session_cap)
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
        raise Unauthenticated("Wrong email or password.", code="invalid_credentials")
    assert user.password_hash is not None  # noqa: S101 - verify() is False for null hashes
    if ctx.passwords.needs_rehash(user.password_hash):
        user.password_hash = ctx.passwords.hash(password)
    user.last_login_at = utcnow()
    return user


def refresh_session(db: Session, ctx: AuthContext, presented: str) -> TokenPair:
    now = utcnow()
    row = db.scalar(
        select(RefreshToken).where(RefreshToken.token_hash == hash_refresh_token(presented))
    )
    if row is None or row.expires_at <= now:
        raise Unauthenticated("Session expired, please sign in again.")
    user = db.get(User, row.user_id)
    if user is None or not user.is_active:
        raise Unauthenticated("Session expired, please sign in again.")

    if row.revoked_at is not None:
        _revoke_family(db, row.family_id, now)
        db.commit()
        raise Unauthenticated(
            "Session revoked, please sign in again.", code="refresh_reuse_detected"
        )

    if row.used_at is not None:
        successor = db.get(RefreshToken, row.replaced_by_id) if row.replaced_by_id else None
        grace = timedelta(seconds=ctx.settings.refresh_reuse_grace_seconds)
        lost_response = (
            now - row.used_at <= grace
            and successor is not None
            and successor.used_at is None
            and successor.revoked_at is None
        )
        if not lost_response:
            _revoke_family(db, row.family_id, now)
            db.commit()
            raise Unauthenticated(
                "Session revoked, please sign in again.", code="refresh_reuse_detected"
            )
        assert successor is not None  # noqa: S101 - checked in lost_response
        successor.revoked_at = now

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


def _revoke_family(db: Session, family_id: uuid.UUID, now: datetime) -> None:
    db.execute(
        update(RefreshToken)
        .where(RefreshToken.family_id == family_id, RefreshToken.revoked_at.is_(None))
        .values(revoked_at=now)
    )


def revoke_all_sessions(db: Session, user: User, *, keep_family: uuid.UUID | None = None) -> None:
    now = utcnow()
    query = update(RefreshToken).where(
        RefreshToken.user_id == user.id, RefreshToken.revoked_at.is_(None)
    )
    if keep_family is not None:
        query = query.where(RefreshToken.family_id != keep_family)
    db.execute(query.values(revoked_at=now))


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


def change_password(
    db: Session,
    ctx: AuthContext,
    user: User,
    *,
    current_password: str,
    new_password: str,
    session_id: uuid.UUID,
) -> TokenPair:
    """Changes the password and signs out every *other* session.

    Existing access tokens die (token_version bump), so the caller gets a fresh pair for the
    current session.
    """
    if not ctx.passwords.verify(user.password_hash, current_password):
        raise Unauthenticated("Wrong password.", code="invalid_credentials")
    _check_password_rules(new_password, user.email)
    user.password_hash = ctx.passwords.hash(new_password)
    user.token_version += 1
    revoke_all_sessions(db, user, keep_family=session_id)
    current = db.scalar(
        select(RefreshToken)
        .where(
            RefreshToken.family_id == session_id,
            RefreshToken.revoked_at.is_(None),
            RefreshToken.used_at.is_(None),
        )
        .order_by(RefreshToken.created_at.desc())
        .limit(1)
    )
    started = current.session_started_at if current else utcnow()
    if current is not None:
        current.revoked_at = utcnow()
    pair, _ = _issue_tokens(
        db,
        ctx,
        user,
        family_id=session_id,
        session_started_at=started,
        device_label=current.device_label if current else None,
    )
    db.commit()
    return pair
