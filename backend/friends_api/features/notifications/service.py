"""The notification job (contract section 18.4), run by ``cli send-notifications`` from cron.

What's announced:

- ``group_log`` rows of the last :data:`LOG_LOOKBACK` (so a missed run catches up):
  ``poll.created`` (polls), ``wheel.accepted`` (wheel), ``member.joined`` (members) and
  ``activity.status_changed`` to ``scheduled`` (plans, to the members interested in it); never
  to whoever did it.
- Open polls closing within a day, to members who haven't voted (polls); not for polls that
  only ever had less than a day.
- My occurrences from ``GET /me/calendar``, member birthdays included and my own excluded
  (reminders): timed ones within 24 hours and all-day ones from 18:00 the evening before, by
  email and push, in one message per run; timed ones within the hour again, by push only.

Each notice goes by push to every browser the user subscribed, and by email when
``notify_email`` is on and the address is verified. Kinds can be switched off per user, groups
muted per member. Each (user, channel, kind, ref) is recorded before it is sent: at most once.
"""

import logging
import uuid
from collections.abc import Iterable
from dataclasses import dataclass, field
from datetime import datetime, time, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import ColumnElement, delete, select
from sqlalchemy.orm import Session

from friends_api.core.config import Settings
from friends_api.core.mail import Mailer, send_safely
from friends_api.core.webpush import Pusher, PushResult, PushTarget
from friends_api.features.activities.models import Activity, ActivityInterest
from friends_api.features.auth.models import User
from friends_api.features.emails.tokens import NotificationKind
from friends_api.features.events import calendar
from friends_api.features.events.models import EventKind
from friends_api.features.events.schemas import Occurrence, OccurrenceSource
from friends_api.features.group_log.models import GroupLog
from friends_api.features.groups.models import Group, Membership
from friends_api.features.notifications import messages
from friends_api.features.notifications.messages import Notice, ReminderItem
from friends_api.features.notifications.models import NotificationDelivery, PushSubscription
from friends_api.features.polls.models import Poll, PollVote

logger = logging.getLogger(__name__)

LOG_LOOKBACK = timedelta(hours=6)
REMINDER_HORIZON = timedelta(hours=24)
SOON_HORIZON = timedelta(hours=1)
POLL_CLOSING_HORIZON = timedelta(hours=24)
ALL_DAY_REMINDER_TIME = time(18, 0)
"""All-day occurrences are announced from this time the evening before."""
DELIVERY_RETENTION = timedelta(days=60)

EMAIL, PUSH = "email", "push"
_PREFS = {
    NotificationKind.POLLS: User.notify_polls,
    NotificationKind.WHEEL: User.notify_wheel,
    NotificationKind.REMINDERS: User.notify_reminders,
    NotificationKind.MEMBERS: User.notify_members,
    NotificationKind.PLANS: User.notify_plans,
}


@dataclass(slots=True)
class JobReport:
    sent: dict[str, int] = field(default_factory=dict)
    """By ``<channel>:<kind>``."""
    failed: int = 0

    def count(self, channel: str, kind: NotificationKind, ok: bool) -> None:
        if ok:
            key = f"{channel}:{kind.value}"
            self.sent[key] = self.sent.get(key, 0) + 1
        else:
            self.failed += 1


@dataclass(slots=True)
class _Run:
    db: Session
    settings: Settings
    mailer: Mailer
    pusher: Pusher
    now: datetime
    report: JobReport

    def claim(
        self, user_id: uuid.UUID, channels: list[str], kind: NotificationKind, refs: Iterable[str]
    ) -> list[str]:
        """The refs never delivered to the user on **any** channel, now recorded for
        ``channels`` (the caller commits). Switching email on, or a new browser, doesn't
        resend what already arrived elsewhere."""
        wanted = list(dict.fromkeys(refs))
        if not wanted or not channels:
            return []
        done = set(
            self.db.scalars(
                select(NotificationDelivery.ref).where(
                    NotificationDelivery.user_id == user_id,
                    NotificationDelivery.kind == kind,
                    NotificationDelivery.ref.in_(wanted),
                )
            )
        )
        new = [ref for ref in wanted if ref not in done]
        self.db.add_all(
            NotificationDelivery(user_id=user_id, channel=channel, kind=kind, ref=ref)
            for ref in new
            for channel in channels
        )
        return new

    def channels(
        self, user: User, *, email: bool = True
    ) -> tuple[list[str], list[PushSubscription]]:
        """Push to each subscribed browser; email when switched on and verified."""
        targets = list(
            self.db.scalars(select(PushSubscription).where(PushSubscription.user_id == user.id))
        )
        channels = [PUSH] if targets else []
        if email and user.notify_email and user.email_verified_at is not None:
            channels.append(EMAIL)
        return channels, targets

    def push_all(
        self, targets: list[PushSubscription], kind: NotificationKind, payload: bytes
    ) -> None:
        for target in targets:
            result = self.pusher.push(
                PushTarget(target.endpoint, target.p256dh, target.auth), payload
            )
            if result == PushResult.GONE:
                self.db.delete(target)
            elif result == PushResult.SENT:
                target.last_used_at = self.now
            self.report.count(PUSH, kind, result == PushResult.SENT)
        self.db.commit()

    def deliver(self, user: User, notice: Notice) -> None:
        """Sends ``notice`` by push and, if switched on, email, unless it already went out."""
        channels, targets = self.channels(user, email=notice.email)
        if not self.claim(user.id, channels, notice.kind, [notice.ref]):
            return
        self.db.commit()
        if EMAIL in channels:
            email = messages.notice_email(self.settings, user, notice)
            self.report.count(EMAIL, notice.kind, send_safely(self.mailer, email))
        if PUSH in channels:
            self.push_all(targets, notice.kind, messages.push_payload(notice))


def _audience(kind: NotificationKind) -> list[ColumnElement[bool]]:
    return [User.deleted_at.is_(None), _PREFS[kind].is_(True)]


def _members(
    db: Session, group_id: uuid.UUID, kind: NotificationKind, *, but: uuid.UUID | None
) -> list[User]:
    """The group's members who want ``kind`` and haven't muted it, except ``but``."""
    stmt = (
        select(User)
        .join(Membership, Membership.user_id == User.id)
        .where(
            Membership.group_id == group_id,
            Membership.notifications_muted.is_(False),
            *_audience(kind),
        )
    )
    if but is not None:
        stmt = stmt.where(User.id != but)
    return list(db.scalars(stmt))


def _name(db: Session, user_id: uuid.UUID | None) -> str:
    user = db.get(User, user_id) if user_id else None
    return user.display_name if user else "Someone"


def _log_notices(run: _Run, row: GroupLog) -> list[tuple[User, Notice]]:
    db, settings = run.db, run.settings
    group = db.get(Group, row.group_id)
    if group is None or row.subject_id is None:
        return []
    ref = str(row.id)
    if row.action == "poll.created":
        poll = db.get(Poll, row.subject_id)
        activity = db.get(Activity, poll.activity_id) if poll else None
        if poll is None or activity is None or not poll.is_open(run.now):
            return []
        notice = Notice(
            kind=NotificationKind.POLLS,
            ref=ref,
            title=f"New poll in {group.name}: {poll.question}",
            body=f"{_name(db, row.actor_id)} started a poll on {activity.title}.",
            url=messages.activity_link(settings, group.id, activity.id),
            action="Vote",
        )
        return [(u, notice) for u in _members(db, group.id, notice.kind, but=row.actor_id)]
    if row.action == "wheel.accepted":
        raw = row.data.get("activity_id")
        activity = db.get(Activity, uuid.UUID(raw)) if raw else None
        if activity is None:
            return []
        notice = Notice(
            kind=NotificationKind.WHEEL,
            ref=ref,
            title=f"The wheel picked {activity.title} in {group.name}",
            body=f"{_name(db, row.actor_id)} spun the wheel, and the group is going with "
            f"{activity.title}.",
            url=messages.activity_link(settings, group.id, activity.id),
            action="See it",
        )
        return [(u, notice) for u in _members(db, group.id, notice.kind, but=row.actor_id)]
    if row.action == "member.joined" and row.data.get("via") != "create":
        name = _name(db, row.subject_id)
        notice = Notice(
            kind=NotificationKind.MEMBERS,
            ref=ref,
            title=f"{name} joined {group.name}",
            body=f"Say hi to {name} in {group.name}.",
            url=messages.group_link(settings, group.id),
            action="See the group",
        )
        return [(u, notice) for u in _members(db, group.id, notice.kind, but=row.subject_id)]
    if row.action == "activity.status_changed" and row.data.get("to") == "scheduled":
        activity = db.get(Activity, row.subject_id)
        if activity is None:
            return []
        notice = Notice(
            kind=NotificationKind.PLANS,
            ref=ref,
            title=f"{activity.title} is happening in {group.name}",
            body=f"{activity.title}, which you're interested in, has been scheduled.",
            url=messages.activity_link(settings, group.id, activity.id),
            action="See when",
        )
        interested = select(ActivityInterest.user_id).where(
            ActivityInterest.activity_id == activity.id
        )
        return [
            (u, notice)
            for u in _members(db, group.id, notice.kind, but=row.actor_id)
            if u.id in set(db.scalars(interested))
        ]
    return []


_LOG_ACTIONS = ["poll.created", "wheel.accepted", "member.joined", "activity.status_changed"]


def _from_group_log(run: _Run) -> None:
    rows = run.db.scalars(
        select(GroupLog)
        .where(GroupLog.action.in_(_LOG_ACTIONS), GroupLog.created_at > run.now - LOG_LOOKBACK)
        .order_by(GroupLog.created_at)
    ).all()
    for row in rows:
        for user, notice in _log_notices(run, row):
            run.deliver(user, notice)


def _closing_polls(run: _Run) -> None:
    db = run.db
    polls = db.scalars(
        select(Poll).where(
            Poll.closed_at.is_(None),
            Poll.closes_at.is_not(None),
            Poll.closes_at > run.now,
            Poll.closes_at <= run.now + POLL_CLOSING_HORIZON,
        )
    ).all()
    for poll in polls:
        assert poll.closes_at is not None  # noqa: S101 - filtered above
        if poll.created_at > poll.closes_at - POLL_CLOSING_HORIZON:
            continue  # its "new poll" notice already said it closes soon
        group = db.get(Group, poll.group_id)
        activity = db.get(Activity, poll.activity_id)
        if group is None or activity is None:
            continue
        notice = Notice(
            kind=NotificationKind.POLLS,
            ref=f"{poll.id}:closing",
            title=f"Last day to vote in {group.name}: {poll.question}",
            body=f"The poll on {activity.title} closes soon and you haven't voted yet.",
            url=messages.activity_link(run.settings, group.id, activity.id),
            action="Vote",
        )
        voters = set(db.scalars(select(PollVote.user_id).where(PollVote.poll_id == poll.id)))
        for user in _members(db, group.id, notice.kind, but=None):
            if user.id not in voters:
                run.deliver(user, notice)


def _due(occurrence: Occurrence, now: datetime, zone: ZoneInfo, horizon: timedelta) -> bool:
    if occurrence.all_day:
        if horizon < REMINDER_HORIZON:
            return False  # no hour-before reminder for all-day things
        assert occurrence.start_date is not None  # noqa: S101 - all-day occurrences have dates
        start = datetime.combine(
            occurrence.start_date - timedelta(days=1), ALL_DAY_REMINDER_TIME, zone
        )
        end = datetime.combine(occurrence.start_date + timedelta(days=1), time(0), zone)
        return start <= now < end
    assert occurrence.starts_at is not None  # noqa: S101 - timed occurrences have instants
    return now < occurrence.starts_at <= now + horizon


def _title(occurrence: Occurrence) -> str:
    if occurrence.kind is EventKind.BIRTHDAY:
        return f"🎂 {occurrence.title}'s birthday"
    return occurrence.title


def _reminders(run: _Run) -> None:
    db, kind = run.db, NotificationKind.REMINDERS
    for user in db.scalars(select(User).where(*_audience(kind))).all():
        muted = set(
            db.scalars(
                select(Membership.group_id).where(
                    Membership.user_id == user.id, Membership.notifications_muted.is_(True)
                )
            )
        )
        zone = ZoneInfo(user.timezone)
        today = run.now.astimezone(zone).date()
        query = calendar.CalendarQuery(
            from_date=today, to_date=today + timedelta(days=2), tz=user.timezone
        )
        occurrences = [
            o
            for o in calendar.my_calendar(db, user, query).occurrences
            if (o.group_id is None or o.group_id not in muted)
            and not (o.source is OccurrenceSource.MEMBER_BIRTHDAY and o.user_id == user.id)
        ]
        group_ids = {o.group_id for o in occurrences if o.group_id}
        names = (
            dict(db.execute(select(Group.id, Group.name).where(Group.id.in_(group_ids))).all())
            if group_ids
            else {}
        )
        for horizon, suffix in ((REMINDER_HORIZON, ""), (SOON_HORIZON, ":1h")):
            items = [
                ReminderItem(
                    ref=f"{o.event_id or o.user_id}:{o.occurrence_key}{suffix}",
                    title=_title(o),
                    group_name=names.get(group_id) if (group_id := o.group_id) else None,
                    all_day=o.all_day,
                    start_date=o.start_date,
                    starts_at=o.starts_at,
                )
                for o in occurrences
                if _due(o, run.now, zone, horizon)
            ]
            if items:
                _deliver_reminders(run, user, items, push_only=bool(suffix))


def _deliver_reminders(
    run: _Run, user: User, items: list[ReminderItem], *, push_only: bool
) -> None:
    """One message listing the items not delivered yet."""
    kind = NotificationKind.REMINDERS
    channels, targets = run.channels(user, email=not push_only)
    new = set(run.claim(user.id, channels, kind, [item.ref for item in items]))
    run.db.commit()
    fresh = [item for item in items if item.ref in new]
    if not fresh:
        return
    notice = messages.reminder_notice(run.settings, user, fresh, now=run.now, push_only=push_only)
    if EMAIL in channels:
        email = messages.notice_email(run.settings, user, notice)
        run.report.count(EMAIL, kind, send_safely(run.mailer, email))
    if PUSH in channels:
        run.push_all(targets, kind, messages.push_payload(notice))


def send_notifications(
    db: Session, settings: Settings, mailer: Mailer, pusher: Pusher, now: datetime
) -> JobReport:
    """One run of the job; safe to run as often as wanted (every 5 minutes in production)."""
    run = _Run(db, settings, mailer, pusher, now, JobReport())
    _from_group_log(run)
    _closing_polls(run)
    _reminders(run)
    db.execute(
        delete(NotificationDelivery).where(
            NotificationDelivery.created_at < now - DELIVERY_RETENTION
        )
    )
    db.commit()
    return run.report


def unsubscribe(db: Session, user_id: uuid.UUID, kind: NotificationKind) -> None:
    user = db.get(User, user_id)
    if user is None:
        return
    setattr(user, f"notify_{kind.value}", False)
    db.commit()
