"""The webcal feed (contract section 5.10): my calendar as an iCalendar file at a secret URL,
for calendar apps that subscribe without signing in."""

import secrets
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.orm import Session

from friends_api.core.config import Settings
from friends_api.core.errors import NotFound
from friends_api.features.auth.models import User
from friends_api.features.calendar_feed import ics
from friends_api.features.calendar_feed.schemas import CalendarFeed
from friends_api.features.events import calendar
from friends_api.features.groups.models import Group

FEED_PATH = "/api/v1/calendar-feed"
"""The feed's path prefix; the access log masks what follows it."""
PAST_DAYS = 30
FUTURE_DAYS = 365
"""The feed covers ``[today - 30 days, today + 365 days)`` in my timezone (within the
calendar's 400-day limit)."""
CALENDAR_NAME = "Friends"


def _feed(settings: Settings, token: str | None) -> CalendarFeed:
    if token is None:
        return CalendarFeed(url=None, webcal_url=None)
    url = f"{settings.public_app_url}{FEED_PATH}/{token}.ics"
    return CalendarFeed(url=url, webcal_url="webcal://" + url.split("://", 1)[1])


def get_feed(settings: Settings, user: User) -> CalendarFeed:
    return _feed(settings, user.calendar_feed_token)


def reset_feed(db: Session, settings: Settings, user: User) -> CalendarFeed:
    """Turns the feed on with a new secret; any previous URL stops working."""
    user.calendar_feed_token = secrets.token_urlsafe(32)
    db.commit()
    return _feed(settings, user.calendar_feed_token)


def disable_feed(db: Session, user: User) -> None:
    user.calendar_feed_token = None
    db.commit()


def feed_owner(db: Session, token: str) -> User:
    """The active user whose feed ``token`` is. Unknown, revoked or deleted: 404."""
    user = db.scalar(select(User).where(User.calendar_feed_token == token)) if token else None
    if user is None or not user.is_active:
        raise NotFound("No such calendar feed.")
    return user


def render_feed(db: Session, user: User, now: datetime) -> str:
    """``GET /me/calendar`` for the feed's window, as iCalendar."""
    zone = user.timezone if user.timezone else "UTC"
    today = now.astimezone(ZoneInfo(zone)).date()
    query = calendar.CalendarQuery(
        from_date=today - timedelta(days=PAST_DAYS), to_date=today + timedelta(days=FUTURE_DAYS)
    )
    occurrences = calendar.my_calendar(db, user, query).occurrences
    group_ids = {occurrence.group_id for occurrence in occurrences if occurrence.group_id}
    names = (
        dict(db.execute(select(Group.id, Group.name).where(Group.id.in_(group_ids))).all())
        if group_ids
        else {}
    )
    return ics.render(occurrences, names, calendar_name=CALENDAR_NAME, now=now)
