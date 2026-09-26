"""A group's recap for a month or a year (contract section 14): its highlight stats, computed
live from the activities, polls, spins and ``group_log`` rows of the period.

Periods are calendar months or years in the group's timezone: ``[start, end)`` local midnights,
compared as UTC instants.
"""

import uuid
from collections import Counter, defaultdict
from datetime import UTC, date, datetime, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from friends_api.core.db import utcnow
from friends_api.core.errors import FieldError, Unprocessable
from friends_api.features.activities.models import Activity, ActivityInterest, ActivityStatus
from friends_api.features.auth.models import User
from friends_api.features.categories.service import CategoryIndex
from friends_api.features.group_log.models import GroupLog
from friends_api.features.groups.service import GroupAccess
from friends_api.features.polls.models import Poll, PollVote
from friends_api.features.recap.schemas import (
    EARLIEST_YEAR,
    MAX_MEMORIES,
    TOP_CATEGORIES,
    TOP_PLANNERS,
    Recap,
    RecapActivity,
    RecapCategory,
    RecapIdea,
    RecapMonth,
    RecapPeriod,
    RecapPlanner,
    RecapPoll,
    RecapWait,
)
from friends_api.features.users.schemas import UserPublic
from friends_api.features.wheel.models import WheelSpin

PLANNER_ACTIONS = ("activity.created", "event.created", "poll.created", "activity.status_changed")
"""What makes a planner: ideas, events and polls created, and activities marked done."""

_BACKLOG = (ActivityStatus.IDEA, ActivityStatus.PLANNING)


def period_start(period: RecapPeriod, day: date) -> date:
    """The first day of ``day``'s month or year."""
    return day.replace(day=1) if period is RecapPeriod.MONTH else day.replace(month=1, day=1)


def period_end(period: RecapPeriod, start: date) -> date:
    """The first day of the period after the one starting on ``start``."""
    if period is RecapPeriod.YEAR:
        return start.replace(year=start.year + 1)
    if start.month == 12:
        return start.replace(year=start.year + 1, month=1)
    return start.replace(month=start.month + 1)


def _midnight(day: date, zone: ZoneInfo) -> datetime:
    """``day``'s start in ``zone``, as a UTC instant."""
    return datetime(day.year, day.month, day.day, tzinfo=zone).astimezone(UTC)


def _invalid_start(message: str) -> Unprocessable:
    return Unprocessable(
        message, errors=[FieldError(field="query.start", message=message, type="value_error")]
    )


def resolve_start(period: RecapPeriod, start: date | None, today: date) -> date:
    """The period's first day: ``start``, or the current period's when omitted. Only past and
    current periods have a recap."""
    current = period_start(period, today)
    if start is None:
        return current
    if start != period_start(period, start):
        unit = "month" if period is RecapPeriod.MONTH else "year"
        raise _invalid_start(f"Must be the first day of a {unit}.")
    if start.year < EARLIEST_YEAR:
        raise _invalid_start(f"Recaps start in {EARLIEST_YEAR}.")
    if start > current:
        raise _invalid_start("This period hasn't started yet.")
    return start


def _recap_activity(activity: Activity, categories: CategoryIndex) -> RecapActivity:
    assert activity.completed_at is not None  # noqa: S101 - only memories are listed
    return RecapActivity(
        id=activity.id,
        title=activity.title,
        category_id=activity.category_id,
        color=categories.effective_color(activity.category_id),
        created_at=activity.created_at,
        completed_at=activity.completed_at,
    )


def _top_categories(memories: list[Activity], categories: CategoryIndex) -> list[RecapCategory]:
    counts: Counter[uuid.UUID] = Counter()
    for activity in memories:
        category = categories.get(activity.category_id)
        if category is not None:
            counts[(categories.parent_of(category) or category).id] += 1
    ranked = [
        RecapCategory(
            id=category.id,
            name=category.name,
            color=category.color,
            icon=category.icon,
            count=count,
        )
        for category_id, count in counts.items()
        if (category := categories.get(category_id)) is not None
    ]
    ranked.sort(key=lambda c: (-c.count, c.name.lower(), str(c.id)))
    return ranked[:TOP_CATEGORIES]


def _longest_wait(memories: list[Activity], categories: CategoryIndex) -> RecapWait | None:
    """The memory with the longest ``created_at`` → ``completed_at``; the earliest on a tie."""
    best: tuple[Activity, timedelta] | None = None
    for activity in memories:
        assert activity.completed_at is not None  # noqa: S101 - memories are completed
        wait = activity.completed_at - activity.created_at
        if best is None or wait > best[1]:
            best = (activity, wait)
    if best is None:
        return None
    activity, wait = best
    return RecapWait(activity=_recap_activity(activity, categories), days=max(wait.days, 0))


def _planners(db: Session, rows: list[GroupLog]) -> list[RecapPlanner]:
    tallies: dict[uuid.UUID, Counter[str]] = defaultdict(Counter)
    for row in rows:
        if row.actor_id is None:
            continue
        if row.action == "activity.status_changed":
            if row.data.get("to") != ActivityStatus.DONE:
                continue
            tallies[row.actor_id]["done"] += 1
        else:
            tallies[row.actor_id][row.action.split(".")[0]] += 1
    if not tallies:
        return []
    users = {user.id: user for user in db.scalars(select(User).where(User.id.in_(tallies)))}
    planners = [
        RecapPlanner(
            user=UserPublic.from_user(users[user_id]),
            score=sum(tally.values()),
            ideas=tally["activity"],
            events=tally["event"],
            polls=tally["poll"],
            done=tally["done"],
        )
        for user_id, tally in tallies.items()
        if user_id in users
    ]
    planners.sort(key=lambda p: (-p.score, p.user.display_name.lower(), str(p.user.id)))
    return planners[:TOP_PLANNERS]


def _top_poll(db: Session, group_id: uuid.UUID, begin: datetime, end: datetime) -> RecapPoll | None:
    voters = func.count(func.distinct(PollVote.user_id))
    row = db.execute(
        select(Poll, Activity.title, voters)
        .join(PollVote, PollVote.poll_id == Poll.id)
        .join(Activity, Activity.id == Poll.activity_id)
        .where(Poll.group_id == group_id, Poll.created_at >= begin, Poll.created_at < end)
        .group_by(Poll.id, Activity.title)
        .order_by(voters.desc(), Poll.created_at, Poll.id)
        .limit(1)
    ).first()
    if row is None:
        return None
    poll, title, count = row
    return RecapPoll(
        id=poll.id,
        question=poll.question,
        activity_id=poll.activity_id,
        activity_title=title,
        voters=count,
    )


def _most_wanted(
    db: Session, group_id: uuid.UUID, end: datetime, categories: CategoryIndex
) -> RecapIdea | None:
    interested = func.count(ActivityInterest.user_id)
    row = db.execute(
        select(Activity, interested)
        .join(ActivityInterest, ActivityInterest.activity_id == Activity.id)
        .where(
            Activity.group_id == group_id,
            Activity.status.in_(_BACKLOG),
            Activity.created_at < end,
            ActivityInterest.created_at < end,
        )
        .group_by(Activity.id)
        .order_by(interested.desc(), Activity.created_at, Activity.id)
        .limit(1)
    ).first()
    if row is None:
        return None
    activity, count = row
    return RecapIdea(
        activity_id=activity.id,
        title=activity.title,
        color=categories.effective_color(activity.category_id),
        interested=count,
    )


def _busiest_month(memories: list[Activity], zone: ZoneInfo) -> RecapMonth | None:
    counts: Counter[date] = Counter()
    for activity in memories:
        assert activity.completed_at is not None  # noqa: S101 - memories are completed
        local = activity.completed_at.astimezone(zone)
        counts[date(local.year, local.month, 1)] += 1
    if not counts:
        return None
    month, count = min(counts.items(), key=lambda item: (-item[1], item[0]))
    return RecapMonth(month=month, count=count)


def group_recap(
    db: Session,
    access: GroupAccess,
    period: RecapPeriod,
    start: date | None,
    *,
    now: datetime | None = None,
) -> Recap:
    group = access.group
    zone = ZoneInfo(group.timezone)
    now = now or utcnow()
    first = resolve_start(period, start, now.astimezone(zone).date())
    last = period_end(period, first)
    begin, end = _midnight(first, zone), _midnight(last, zone)
    categories = CategoryIndex.load(db, group.id)

    memories = list(
        db.scalars(
            select(Activity)
            .where(
                Activity.group_id == group.id,
                Activity.status == ActivityStatus.DONE,
                Activity.completed_at >= begin,
                Activity.completed_at < end,
            )
            .order_by(Activity.completed_at, Activity.id)
        )
    )
    log = list(
        db.scalars(
            select(GroupLog).where(
                GroupLog.group_id == group.id,
                GroupLog.created_at >= begin,
                GroupLog.created_at < end,
                or_(GroupLog.action.in_(PLANNER_ACTIONS), GroupLog.action == "member.joined"),
            )
        )
    )
    actions = Counter(row.action for row in log)
    wheel_decisions = db.scalar(
        select(func.count())
        .select_from(WheelSpin)
        .where(
            WheelSpin.group_id == group.id,
            WheelSpin.accepted_at >= begin,
            WheelSpin.accepted_at < end,
        )
    )
    return Recap(
        period=period,
        start=first,
        end=last,
        timezone=group.timezone,
        complete=end <= now,
        memory_count=len(memories),
        memories=[_recap_activity(a, categories) for a in memories[:MAX_MEMORIES]],
        planners=_planners(db, [row for row in log if row.action in PLANNER_ACTIONS]),
        top_categories=_top_categories(memories, categories),
        ideas_added=actions["activity.created"],
        events_planned=actions["event.created"],
        polls_created=actions["poll.created"],
        wheel_decisions=wheel_decisions or 0,
        new_members=actions["member.joined"],
        top_poll=_top_poll(db, group.id, begin, end),
        longest_wait=_longest_wait(memories, categories),
        busiest_month=_busiest_month(memories, zone) if period is RecapPeriod.YEAR else None,
        most_wanted=_most_wanted(db, group.id, end, categories),
    )
