"""The transactional emails (contract section 18.2-18.3) and the links in them."""

from urllib.parse import quote

from friends_api.core.config import Settings
from friends_api.core.mail import Email
from friends_api.features.auth.models import User
from friends_api.features.emails.render import Action, compose

API_PREFIX = "/api/v1"


def app_link(settings: Settings, path: str, token: str | None = None) -> str:
    """``PUBLIC_APP_URL`` + an app route, with ``?token=`` when given."""
    url = f"{settings.public_app_url}{path}"
    return f"{url}?token={quote(token, safe='')}" if token else url


def verification_email(settings: Settings, user: User, token: str) -> Email:
    return compose(
        to=user.email,
        subject="Confirm your email for Friends",
        paragraphs=[
            f"Hi {user.display_name},",
            "Please confirm that this is your email address. Friends uses it to send you a "
            "password reset link if you ever need one, and the notifications you choose.",
        ],
        action=Action("Confirm my email", app_link(settings, "/verify-email", token)),
        after=["The link works for 7 days."],
        footer="You get this because someone signed up for Friends with this address. "
        "If it wasn't you, ignore this email.",
    )


def password_reset_email(settings: Settings, user: User, token: str) -> Email:
    return compose(
        to=user.email,
        subject="Reset your Friends password",
        paragraphs=[
            f"Hi {user.display_name},",
            "Someone asked to reset the password of your Friends account. If it was you, choose "
            "a new password:",
        ],
        action=Action("Choose a new password", app_link(settings, "/reset-password", token)),
        after=[
            "The link works once, for 1 hour. Choosing a new password signs you out on every "
            "device.",
            "If it wasn't you, ignore this email: your password stays the same.",
        ],
    )


def invite_email(
    settings: Settings, *, to: str, inviter: User, group_name: str, invite_url: str
) -> Email:
    return compose(
        to=to,
        subject=f"{inviter.display_name} invited you to {group_name} on Friends",
        paragraphs=[
            "Hi,",
            f"{inviter.display_name} invited you to join {group_name} on Friends, an app where "
            "friends keep their ideas for things to do, vote on them and plan them together.",
        ],
        action=Action(f"Join {group_name}", invite_url),
        footer=f"{inviter.display_name} entered this address in Friends. If you don't know "
        "them, ignore this email: you won't hear from us again.",
    )
