"""Password reset and email verification (contract sections 18.2 and 18.3).

Each function returns the email to send (or None); the router sends it after the response.
"""

from sqlalchemy import select
from sqlalchemy.orm import Session

from friends_api.core.mail import Email
from friends_api.features.auth.models import EmailTokenPurpose, User
from friends_api.features.auth.service import (
    AuthContext,
    check_password_rules,
    normalize_email,
    revoke_all_sessions,
)
from friends_api.features.emails import messages, tokens


def request_password_reset(db: Session, ctx: AuthContext, email: str) -> Email | None:
    """A reset link for a **verified** address of an active account; otherwise nothing, and
    the caller can't tell which (no account enumeration). An unverified address could be a
    typo that belongs to someone else, who must not get a way into the account."""
    user = db.scalar(
        select(User).where(User.email == normalize_email(email), User.deleted_at.is_(None))
    )
    if user is None or user.email_verified_at is None:
        return None
    token = tokens.issue_token(db, user, EmailTokenPurpose.RESET_PASSWORD)
    db.commit()
    return messages.password_reset_email(ctx.settings, user, token)


def reset_password(db: Session, ctx: AuthContext, token: str, new_password: str) -> None:
    """Sets the password and signs out every session, like ``reset-password`` in the CLI."""
    user = tokens.consume_token(db, token, EmailTokenPurpose.RESET_PASSWORD)
    check_password_rules(new_password, user.email)
    user.password_hash = ctx.passwords.hash(new_password)
    user.token_version += 1
    revoke_all_sessions(db, user)
    tokens.mark_verified(user)  # the link reached the inbox
    db.commit()


def verification_email(db: Session, ctx: AuthContext, user: User) -> Email | None:
    """A new verification link, or nothing when the address is already verified. Commits."""
    if user.email_verified_at is not None or not user.is_active:
        return None
    token = tokens.issue_token(db, user, EmailTokenPurpose.VERIFY_EMAIL)
    db.commit()
    return messages.verification_email(ctx.settings, user, token)


def verify_email(db: Session, token: str) -> None:
    user = tokens.consume_token(db, token, EmailTokenPurpose.VERIFY_EMAIL)
    tokens.mark_verified(user)
    db.commit()
