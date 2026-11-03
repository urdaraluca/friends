"""The notification job (contract section 18.4), run by ``cli send-notifications`` from cron.

- **Polls and wheel results** come from ``group_log`` (``poll.created``, ``wheel.accepted``) of
  the last :data:`LOG_LOOKBACK`, so a missed run catches up; members other than the actor get
  them.
- **Reminders** cover my occurrences (``GET /me/calendar``, member birthdays included): timed
  ones within the next 24 hours, all-day ones from 18:00 the evening before (in my timezone)
  until the day ends. One email per run lists all of them.

Only active users with a verified address and that kind switched on get anything. Each email is
recorded in ``notification_deliveries`` before it is sent, so nothing is sent twice.
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
from friends_api.core.mail import Email, Mailer, send_safely
from friends_api.features.activities.models import Activity
from friends_api.features.auth.models import User
from friends_api.features.emails.tokens import NotificationKind
from friends_api.features.events import calendar
from friends_api.features.events.models import EventKind
from friends_api.features.events.schemas import Occurrence, OccurrenceSource
from friends_api.features.group_log.models import GroupLog
from friends_api.features.groups.models import Group, Membership
from friends_api.features.notifications import messages
from friends_api.features.notifications.models import NotificationDelivery
from friends_api.features.polls.models import Poll

logger = logging.getLogger(__name__)

LOG_LOOKBACK = timedelta(hours=6)
REMINDER_HORIZON = timedelta(hours=24)
ALL_DAY_REMINDER_TIME = time(18, 0)
"""All-day occurrences are announced from this time the evening before."""
DELIVERY_RETENTION = timedelta(days=60)


@dataclass(slots=True)
class JobReport:
    sent: dict[str, int] = field(default_factory=dict)
    failed: int = 0

    def count(self, kind: NotificationKind, ok: bool) -> None:
        if ok:
            self.sent[kind.value] = self.sent.get(kind.value, 0) + 1
        else:
            self.failed += 1


def _opted_in(kind: NotificationKind) -> ColumnElement[bool]:
    column = {
        NotificationKind.POLLS: User.notify_polls,
        NotificationKind.WHEEL: User.notify_wheel,
        NotificationKind.REMINDERS: User.notify_reminders,
    }[kind]
    return column.is_(True)


def _eligible() -> list[ColumnElement[bool]]:
    return [User.deleted_at.is_(None), User.email_verified_at.is_not(None)]


def _claim(
    db: Session, user_id: uuid.UUID, kind: NotificationKind, refs: Iterable[str]
) -> list[str]:
    """The refs not delivered yet, now recorded as delivered (the caller commits)."""
    wanted = list(dict.fromkeys(refs))
    if not wanted:
        return []
    done = set(
        db.scalars(
            select(NotificationDelivery.ref).where(
                NotificationDelivery.user_id == user_id,
                NotificationDelivery.kind == kind,
                NotificationDelivery.ref.in_(wanted),
            )
        )
    )
    new = [ref for ref in wanted if ref not in done]
    db.add_all(NotificationDelivery(user_id=user_id, kind=kind, ref=ref) for ref in new)
    return new


def _recipients(
    db: Session, group_id: uuid.UUID, kind: NotificationKind, actor_id: uuid.UUID | None
) -> list[User]:
    stmt = (
        select(User)
        .join(Membership, Membership.user_id == User.id)
        .where(Membership.group_id == group_id, _opted_in(kind), *_eligible())
    )
    if actor_id is not None:
        stmt = stmt.where(User.id != actor_id)
    return list(db.scalars(stmt))


def _actor_name(db: Session, actor_id: uuid.UUID | None) -> str:
    actor = db.get(User, actor_id) if actor_id else None
    return actor.display_name if actor else "Someone"


def _log_emails(
    db: Session, settings: Settings, row: GroupLog
) -> tuple[NotificationKind, list[tuple[User, Email]]] | None:
    group = db.get(Group, row.group_id)
    if group is None or row.subject_id is None:
        return None
    if row.action == "poll.created":
        poll = db.get(Poll, row.subject_id)
        activity = db.get(Activity, poll.activity_id) if poll else None
        if poll is None or activity is None or not poll.is_open(row.created_at):
            return None
        kind = NotificationKind.POLLS
        url = messages.activity_link(settings, group.id, activity.id)
        actor = _actor_name(db, row.actor_id)
        return kind, [
            (
                user,
                messages.poll_email(
                    settings,
                    user,
                    actor_name=actor,
                    group_name=group.name,
                    question=poll.question,
                    activity_title=activity.title,
                    url=url,
                ),
            )
            for user in _recipients(db, group.id, kind, row.actor_id)
        ]
    if row.action == "wheel.accepted":
        activity_id = row.data.get("activity_id")
        activity = db.get(Activity, uuid.UUID(activity_id)) if activity_id else None
        if activity is None:
            return None
        kind = NotificationKind.WHEEL
        url = messages.activity_link(settings, group.id, activity.id)
        actor = _actor_name(db, row.actor_id)
        return kind, [
            (
                user,
                messages.wheel_email(
                    settings,
                    user,
                    actor_name=actor,
                    group_name=group.name,
                    activity_title=activity.title,
                    url=url,
                ),
            )
            for user in _recipients(db, group.id, kind, row.actor_id)
        ]
    return None


def _send_group_log(
    db: Session, settings: Settings, mailer: Mailer, now: datetime, report: JobReport
) -> None:
    rows = db.scalars(
        select(GroupLog)
        .where(
            GroupLog.action.in_(["poll.created", "wheel.accepted"]),
            GroupLog.created_at > now - LOG_LOOKBACK,
        )
        .order_by(GroupLog.created_at)
    ).all()
    for row in rows:
        built = _log_emails(db, settings, row)
        if built is None:
            continue
        kind, emails = built
        outgoing = [
            (user, email) for user, email in emails if _claim(db, user.id, kind, [str(row.id)])
        ]
        db.commit()
        for _user, email in outgoing:
            report.count(kind, send_safely(mailer, email))


def _due(occurrence: Occurrence, now: datetime, zone: ZoneInfo) -> bool:
    if occurrence.all_day:
        assert occurrence.start_date is not None  # noqa: S101 - all-day occurrences have dates
        start = datetime.combine(
            occurrence.start_date - timedelta(days=1), ALL_DAY_REMINDER_TIME, zone
        )
        end = datetime.combine(occurrence.start_date + timedelta(days=1), time(0), zone)
        return start <= now < end
    assert occurrence.starts_at is not None  # noqa: S101 - timed occurrences have instants
    return now < occurrence.starts_at <= now + REMINDER_HORIZON


def _reminder_title(occurrence: Occurrence) -> str:
    if occurrence.kind is EventKind.BIRTHDAY:
        return f"🎂 {occurrence.title}'s birthday"
    return occurrence.title


def _send_reminders(
    db: Session, settings: Settings, mailer: Mailer, now: datetime, report: JobReport
) -> None:
    kind = NotificationKind.REMINDERS
    users = db.scalars(select(User).where(_opted_in(kind), *_eligible())).all()
    for user in users:
        zone = ZoneInfo(user.timezone)
        today = now.astimezone(zone).date()
        query = calendar.CalendarQuery(
            from_date=today, to_date=today + timedelta(days=2), tz=user.timezone
        )
        due = [
            occurrence
            for occurrence in calendar.my_calendar(db, user, query).occurrences
            if _due(occurrence, now, zone)
            and not (
                occurrence.source is OccurrenceSource.MEMBER_BIRTHDAY
                and occurrence.user_id == user.id
            )
        ]
        refs = {f"{o.event_id or o.user_id}:{o.occurrence_key}": o for o in due}
        new = _claim(db, user.id, kind, refs)
        db.commit()
        if not new:
            continue
        group_ids = {refs[ref].group_id for ref in new if refs[ref].group_id}
        names = (
            dict(db.execute(select(Group.id, Group.name).where(Group.id.in_(group_ids))).all())
            if group_ids
            else {}
        )
        items = [
            messages.ReminderItem(
                title=_reminder_title(refs[ref]),
                group_name=names.get(group_id) if (group_id := refs[ref].group_id) else None,
                all_day=refs[ref].all_day,
                start_date=refs[ref].start_date,
                starts_at=refs[ref].starts_at,
            )
            for ref in new
        ]
        report.count(
            kind, send_safely(mailer, messages.reminder_email(settings, user, items, now=now))
        )


def send_notifications(db: Session, settings: Settings, mailer: Mailer, now: datetime) -> JobReport:
    """One run of the job; safe to run as often as wanted (every 15 minutes in production)."""
    report = JobReport()
    _send_group_log(db, settings, mailer, now, report)
    _send_reminders(db, settings, mailer, now, report)
    db.execute(
        delete(NotificationDelivery).where(
            NotificationDelivery.created_at < now - DELIVERY_RETENTION
        )
    )
    db.commit()
    return report


def unsubscribe(db: Session, user_id: uuid.UUID, kind: NotificationKind) -> None:
    user = db.get(User, user_id)
    if user is None:
        return
    setattr(user, f"notify_{kind.value}", False)
    db.commit()
