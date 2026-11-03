"""Notification emails (contract section 18.4)."""

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
    NotificationKind.POLLS: "You get this because new polls are on in your Friends settings.",
    NotificationKind.WHEEL: "You get this because wheel results are on in your Friends settings.",
    NotificationKind.REMINDERS: "You get this because reminders are on in your Friends settings.",
}


def _notification(
    settings: Settings,
    user: User,
    kind: NotificationKind,
    *,
    subject: str,
    paragraphs: Sequence[str],
    action: Action,
) -> Email:
    token = unsubscribe_token(settings, user.id, kind)
    return compose(
        to=user.email,
        subject=subject,
        paragraphs=paragraphs,
        action=action,
        footer=_WHY[kind],
        unsubscribe_url=app_link(settings, "/unsubscribe", token),
        one_click_url=app_link(settings, f"{API_PREFIX}/notifications/unsubscribe", token),
    )


def activity_link(settings: Settings, group_id: object, activity_id: object) -> str:
    return app_link(settings, f"/groups/{group_id}/backlog/{activity_id}")


def poll_email(
    settings: Settings,
    user: User,
    *,
    actor_name: str,
    group_name: str,
    question: str,
    activity_title: str,
    url: str,
) -> Email:
    return _notification(
        settings,
        user,
        NotificationKind.POLLS,
        subject=f"New poll in {group_name}: {question}",
        paragraphs=[
            f"{actor_name} started a poll on {activity_title} in {group_name}:",
            question,
        ],
        action=Action("Vote", url),
    )


def wheel_email(
    settings: Settings,
    user: User,
    *,
    actor_name: str,
    group_name: str,
    activity_title: str,
    url: str,
) -> Email:
    return _notification(
        settings,
        user,
        NotificationKind.WHEEL,
        subject=f"The wheel picked {activity_title} in {group_name}",
        paragraphs=[
            f"{actor_name} spun the wheel in {group_name}, and the group is going with "
            f"{activity_title}.",
        ],
        action=Action("See it", url),
    )


@dataclass(frozen=True, slots=True)
class ReminderItem:
    title: str
    group_name: str | None
    all_day: bool
    start_date: date | None
    starts_at: datetime | None


def _when(item: ReminderItem, zone: ZoneInfo, today: date) -> str:
    if item.all_day:
        assert item.start_date is not None  # noqa: S101 - all-day items have dates
        day = item.start_date
        return (
            "today"
            if day == today
            else "tomorrow"
            if day.toordinal() == today.toordinal() + 1
            else day.isoformat()
        )
    assert item.starts_at is not None  # noqa: S101 - timed items have instants
    local = item.starts_at.astimezone(zone)
    day_word = (
        "today"
        if local.date() == today
        else "tomorrow"
        if local.date().toordinal() == today.toordinal() + 1
        else local.date().isoformat()
    )
    return f"{day_word} at {local:%H:%M}"


def reminder_email(
    settings: Settings, user: User, items: Sequence[ReminderItem], *, now: datetime
) -> Email:
    zone = ZoneInfo(user.timezone)
    today = now.astimezone(zone).date()
    lines = [
        f"• {item.title}, {_when(item, zone, today)}"
        + (f" ({item.group_name})" if item.group_name else "")
        for item in items
    ]
    subject = (
        f"Coming up: {items[0].title}, {_when(items[0], zone, today)}"
        if len(items) == 1
        else f"Coming up: {len(items)} things in your calendar"
    )
    return _notification(
        settings,
        user,
        NotificationKind.REMINDERS,
        subject=subject,
        paragraphs=[f"Hi {user.display_name}, here's what's coming up:", *lines],
        action=Action("Open my calendar", app_link(settings, "/calendar")),
    )
