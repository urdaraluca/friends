"""Demo calendar: one-time, weekly, monthly (last Friday) and yearly events, birthday events for
people who aren't on the app, and profile birthdays for the demo users.

Times are wall-clock times in the demo timezone, placed relative to ``ctx.now`` so the calendar
around "today" is always populated. One game night is cancelled, and one idea is scheduled by an
event (which makes it ``scheduled``).
"""

from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy.orm import Session

from friends_api.demo.context import DEMO_TIMEZONE, DemoContext
from friends_api.features.activities.models import Activity, ActivityStatus
from friends_api.features.auth.models import User
from friends_api.features.events import recurrence
from friends_api.features.events import service as events_service
from friends_api.features.events.models import Event, EventException, EventKind
from friends_api.features.events.schemas import EventWrite

_ZONE = ZoneInfo(DEMO_TIMEZONE)

PROFILE_BIRTHDAYS: tuple[tuple[int, int, int | None], ...] = (
    (3, 14, 1994),  # Ana
    (10, 21, None),  # Bogdan
    (2, 29, 1996),  # Carla: 28 February in non-leap years
)
"""(month, day, year) per demo user, in ``ctx.users`` order."""


def _local(day: date, hour: int, minute: int = 0) -> datetime:
    return datetime.combine(day, time(hour, minute), tzinfo=_ZONE)


def _next_weekday(today: date, weekday: int) -> date:
    """The next ``weekday`` (Monday = 0) on or after ``today``."""
    return today + timedelta(days=(weekday - today.weekday()) % 7)


def _idea(ctx: DemoContext, category: str) -> Activity | None:
    category_id = ctx.categories[category].id
    return next(
        (
            a
            for a in ctx.activities
            if a.category_id == category_id and a.status is ActivityStatus.IDEA
        ),
        None,
    )


def _create(db: Session, ctx: DemoContext, user: User, **fields: object) -> Event:
    body = EventWrite.model_validate(fields)
    return events_service.create_event(db, ctx.access(user), body)


def set_profile_birthdays(ctx: DemoContext) -> None:
    for user, (month, day, year) in zip(ctx.users, PROFILE_BIRTHDAYS, strict=True):
        user.birthday_month, user.birthday_day, user.birthday_year = month, day, year


def create_events(db: Session, ctx: DemoContext) -> None:
    ana, bogdan, carla = ctx.users
    today = ctx.now.astimezone(_ZONE).date()
    set_profile_birthdays(ctx)

    # Weekly game night, Thursdays 19:00-22:00, since three weeks ago.
    first_thursday = _next_weekday(today, 3) - timedelta(weeks=3)
    game_night = _create(
        db,
        ctx,
        bogdan,
        kind=EventKind.RECURRING,
        title="Game night",
        description="Bring snacks. Catan or Wingspan, whoever wins the vote.",
        all_day=False,
        starts_at=_local(first_thursday, 19),
        ends_at=_local(first_thursday, 22),
        timezone=DEMO_TIMEZONE,
        rrule="FREQ=WEEKLY;BYDAY=TH",
        category_id=ctx.categories["Games"].id,
        location_name="Bogdan's flat",
    )
    # Next week's game night is off.
    skipped = _local(_next_weekday(today, 3) + timedelta(weeks=1), 19)
    db.add(
        EventException(
            event_id=game_night.id,
            occurrence_key=recurrence.instant_key(skipped),
            created_by_id=bogdan.id,
        )
    )

    # Monthly dinner club on the last Friday, 20:00-23:00.
    month_start = today.replace(day=1)
    _create(
        db,
        ctx,
        ana,
        kind=EventKind.RECURRING,
        title="Dinner club",
        all_day=False,
        starts_at=_local(month_start, 20),
        ends_at=_local(month_start, 23),
        rrule="FREQ=MONTHLY;BYDAY=-1FR",
        category_id=ctx.categories["Food & drinks"].id,
    )

    # A yearly all-day picnic, and a board-game swap every other month (first Sunday) that ends
    # after six times.
    picnic_day = date(today.year, 6, 1)
    _create(
        db,
        ctx,
        carla,
        kind=EventKind.RECURRING,
        title="Anniversary picnic",
        all_day=True,
        start_date=picnic_day,
        rrule="FREQ=YEARLY",
        category_id=ctx.categories["Outdoors"].id,
        location_name="Herăstrău park",
    )
    swap_day = _next_weekday(today, 6)
    _create(
        db,
        ctx,
        carla,
        kind=EventKind.RECURRING,
        title="Board game swap",
        all_day=False,
        starts_at=_local(swap_day, 11),
        ends_at=_local(swap_day, 13),
        rrule="FREQ=MONTHLY;INTERVAL=2;BYDAY=1SU;COUNT=6",
        category_id=ctx.categories["Games"].id,
    )

    # One-time plans: a timed evening that schedules an idea, and a multi-day trip.
    saturday = _next_weekday(today, 5)
    concert = _idea(ctx, "Culture")
    _create(
        db,
        ctx,
        ana,
        kind=EventKind.ONE_TIME,
        title=concert.title if concert else "Concert",
        all_day=False,
        starts_at=_local(saturday, 20),
        ends_at=_local(saturday, 23, 30),
        category_id=ctx.categories["Culture"].id,
        activity_id=concert.id if concert else None,
    )
    trip_start = _next_weekday(today, 4) + timedelta(weeks=2)
    trip = _idea(ctx, "Trips")
    _create(
        db,
        ctx,
        bogdan,
        kind=EventKind.ONE_TIME,
        title=trip.title if trip else "Mountain weekend",
        all_day=True,
        start_date=trip_start,
        end_date=trip_start + timedelta(days=2),
        category_id=ctx.categories["Trips"].id,
        activity_id=trip.id if trip else None,
    )

    # Birthdays of people who aren't on the app.
    for title, born in (("Grandma Elena", date(1948, 11, 12)), ("Mihai", date(1992, 2, 29))):
        _create(
            db,
            ctx,
            ana,
            kind=EventKind.BIRTHDAY,
            title=title,
            all_day=True,
            start_date=born,
        )
