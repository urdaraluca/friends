"""What each notification says, as an email and as a push (contract section 18.4)."""

import json
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import date, datetime
from zoneinfo import ZoneInfo

from friends_api.core.config import Settings
from friends_api.core.mail import Email
from friends_api.features.auth.models import User
from friends_api.features.emails.messages import API_PREFIX, app_link
from friends_api.features.emails.render import Action, compose
from friends_api.features.emails.tokens import NotificationKind, unsubscribe_token

_WHY = {
    NotificationKind.POLLS: "new polls",
    NotificationKind.WHEEL: "wheel results",
    NotificationKind.REMINDERS: "reminders",
    NotificationKind.MEMBERS: "new members",
    NotificationKind.PLANS: "plans for activities you're interested in",
}


@dataclass(frozen=True, slots=True)
class Notice:
    """One thing to tell one user."""

    kind: NotificationKind
    ref: str
    title: str
    """The push title and the email subject."""
    body: str
    """The push text and the email's first lines."""
    url: str
    action: str
    """The email button."""
    email: bool = True
    """False: push only (the hour-before reminder)."""


def notice_email(settings: Settings, user: User, notice: Notice) -> Email:
    token = unsubscribe_token(settings, user.id, notice.kind)
    return compose(
        to=user.email,
        subject=notice.title,
        paragraphs=notice.body.split("\n"),
        action=Action(notice.action, notice.url),
        footer=f"You get this because {_WHY[notice.kind]} are on in your Friends settings.",
        unsubscribe_url=app_link(settings, "/unsubscribe", token),
        one_click_url=app_link(settings, f"{API_PREFIX}/notifications/unsubscribe", token),
    )


def push_payload(notice: Notice) -> bytes:
    """What the service worker shows (``web/push_sw.js``); ``tag`` replaces an older one."""
    return json.dumps(
        {
            "title": notice.title,
            "body": notice.body,
            "url": notice.url,
            "tag": f"{notice.kind.value}:{notice.ref}",
        },
        ensure_ascii=False,
    ).encode()


def activity_link(settings: Settings, group_id: object, activity_id: object) -> str:
    return app_link(settings, f"/groups/{group_id}/backlog/{activity_id}")


def group_link(settings: Settings, group_id: object) -> str:
    return app_link(settings, f"/groups/{group_id}/group")


@dataclass(frozen=True, slots=True)
class ReminderItem:
    ref: str
    title: str
    group_name: str | None
    all_day: bool
    start_date: date | None
    starts_at: datetime | None


def when(item: ReminderItem, zone: ZoneInfo, today: date) -> str:
    def day_word(day: date) -> str:
        if day == today:
            return "today"
        if day.toordinal() == today.toordinal() + 1:
            return "tomorrow"
        return day.isoformat()

    if item.all_day:
        assert item.start_date is not None  # noqa: S101 - all-day items have dates
        return day_word(item.start_date)
    assert item.starts_at is not None  # noqa: S101 - timed items have instants
    local = item.starts_at.astimezone(zone)
    return f"{day_word(local.date())} at {local:%H:%M}"


def reminder_notice(
    settings: Settings, user: User, items: Sequence[ReminderItem], *, now: datetime, push_only: bool
) -> Notice:
    zone = ZoneInfo(user.timezone)
    today = now.astimezone(zone).date()
    lines = [
        f"• {item.title}, {when(item, zone, today)}"
        + (f" ({item.group_name})" if item.group_name else "")
        for item in items
    ]
    title = (
        f"Coming up: {items[0].title}, {when(items[0], zone, today)}"
        if len(items) == 1
        else f"Coming up: {len(items)} things in your calendar"
    )
    return Notice(
        kind=NotificationKind.REMINDERS,
        ref=",".join(item.ref for item in items),
        title=title,
        body="\n".join(lines),
        url=app_link(settings, "/calendar"),
        action="Open my calendar",
        email=not push_only,
    )
