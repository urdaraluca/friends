"""A group's feed (contract section 15): its ``group_log`` rows, newest first, limited to the
actions members care about and to the details they may see."""

import uuid
from collections.abc import Iterable
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from friends_api.core.pagination import paginate
from friends_api.features.activities.models import Activity
from friends_api.features.categories.models import Category
from friends_api.features.events.models import Event
from friends_api.features.feed.schemas import FeedItem, FeedPage
from friends_api.features.group_log.models import GroupLog
from friends_api.features.groups.service import GroupAccess
from friends_api.features.polls.models import Poll
from friends_api.features.users.lookup import public_user, users_by_id
from friends_api.features.wheel.models import WheelSpin

FEED_DATA: dict[str, tuple[str, ...]] = {
    "group.created": (),
    "group.updated": ("fields",),
    "group.ownership_transferred": (),
    "member.joined": ("via",),
    "member.left": ("reason",),
    "member.removed": (),
    "member.role_changed": ("from", "to"),
    "activity.created": ("status",),
    "activity.updated": ("fields",),
    "activity.status_changed": ("from", "to", "via"),
    "activity.deleted": (),
    "activity.interest_added": (),
    "event.created": ("kind",),
    "event.updated": ("kind",),
    "event.deleted": ("kind",),
    "event.occurrence_cancelled": ("occurrence_key",),
    "event.occurrence_restored": ("occurrence_key",),
    "poll.created": ("activity_id",),
    "poll.updated": ("activity_id",),
    "poll.closed": ("activity_id",),
    "poll.reopened": ("activity_id",),
    "poll.deleted": ("activity_id",),
    "poll.option_added": ("label",),
    "poll.voted": (),
    "wheel.spun": ("result_activity_id", "candidate_count"),
    "wheel.accepted": ("activity_id",),
}
"""The actions in the feed, and the ``data`` keys members see for each. Left out: categories
(setup, and a new group logs its defaults), invites, personal settings and removed interest."""

_LOGGED_TITLE = {"activity": "title", "event": "title", "poll": "question", "category": "name"}


def _ids(rows: Iterable[GroupLog], subject_type: str) -> set[uuid.UUID]:
    return {row.subject_id for row in rows if row.subject_type == subject_type and row.subject_id}


def _titles(db: Session, rows: list[GroupLog]) -> dict[tuple[str, uuid.UUID], str]:
    """The current title of each subject that still exists, by (type, id)."""
    titles: dict[tuple[str, uuid.UUID], str] = {}
    lookups: list[tuple[str, Any, Any]] = [
        ("activity", Activity, Activity.title),
        ("event", Event, Event.title),
        ("poll", Poll, Poll.question),
        ("category", Category, Category.name),
    ]
    for subject_type, model, column in lookups:
        ids = _ids(rows, subject_type)
        if ids:
            for subject_id, title in db.execute(
                select(model.id, column).where(model.id.in_(ids))
            ).tuples():
                titles[subject_type, subject_id] = title
    if spin_ids := _ids(rows, "spin"):
        for spin in db.scalars(select(WheelSpin).where(WheelSpin.id.in_(spin_ids))):
            result = spin.candidates[spin.result_index] if spin.candidates else {}
            titles["spin", spin.id] = str(result.get("title", ""))
    if member_ids := _ids(rows, "member"):
        for user_id, user in users_by_id(db, member_ids).items():
            titles["member", user_id] = user.display_name
    return titles


def group_feed(db: Session, access: GroupAccess, *, cursor: str | None, limit: int) -> FeedPage:
    stmt = (
        select(GroupLog)
        .where(GroupLog.group_id == access.group.id, GroupLog.action.in_(FEED_DATA))
        .order_by(GroupLog.created_at.desc(), GroupLog.id.desc())
    )
    rows, next_cursor = paginate(db, stmt, cursor=cursor, limit=limit)
    users = users_by_id(db, (row.actor_id for row in rows))
    titles = _titles(db, rows)
    titles["group", access.group.id] = access.group.name
    items = []
    for row in rows:
        current = (
            titles.get((row.subject_type, row.subject_id))
            if row.subject_type and row.subject_id
            else None
        )
        logged = row.data.get(_LOGGED_TITLE.get(row.subject_type or "", ""))
        items.append(
            FeedItem(
                id=row.id,
                action=row.action,
                actor=public_user(users, row.actor_id),
                subject_type=row.subject_type,
                subject_id=row.subject_id,
                subject_title=current if current is not None else logged,
                subject_exists=current is not None,
                data={k: row.data[k] for k in FEED_DATA[row.action] if k in row.data},
                created_at=row.created_at,
            )
        )
    return FeedPage(items=items, next_cursor=next_cursor)
