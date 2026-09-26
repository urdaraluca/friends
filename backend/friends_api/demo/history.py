"""A year of demo history for the recap (contract section 14). The steps before this one create
their rows through the services, so every ``group_log`` row, interest and membership is stamped
with the real clock. This step moves them to the moments the backdated rows describe, and records
who marked each done activity as done."""

import uuid
from datetime import datetime, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from friends_api.demo.context import DemoContext
from friends_api.features.activities.models import ActivityInterest, ActivityStatus
from friends_api.features.events.models import Event
from friends_api.features.group_log.models import GroupLog
from friends_api.features.polls.models import Poll
from friends_api.features.wheel.models import WheelSpin

HISTORY_DAYS = 366
"""The group and its members date from this many days before ``ctx.now``."""


def create_history(db: Session, ctx: DemoContext) -> None:
    founded = ctx.now - timedelta(days=HISTORY_DAYS)
    ctx.group.created_at = founded
    for index, membership in enumerate(ctx.memberships.values()):
        membership.joined_at = founded + timedelta(days=index)
    activities = {activity.id: activity for activity in ctx.activities}

    moments: dict[tuple[str, uuid.UUID], datetime] = {}
    for activity in ctx.activities:
        moments["activity.created", activity.id] = activity.created_at
    for event in db.scalars(select(Event).where(Event.group_id == ctx.group.id)):
        moments["event.created", event.id] = event.created_at
    for poll in db.scalars(select(Poll).where(Poll.group_id == ctx.group.id)):
        moments["poll.created", poll.id] = poll.created_at
    for spin in db.scalars(select(WheelSpin).where(WheelSpin.group_id == ctx.group.id)):
        moments["wheel.spun", spin.id] = spin.created_at
        if spin.accepted_at is not None:
            moments["wheel.accepted", spin.id] = spin.accepted_at

    for row in db.scalars(select(GroupLog).where(GroupLog.group_id == ctx.group.id)):
        if row.action in ("group.created", "member.joined", "invite.created"):
            row.created_at = founded
        elif row.subject_id is not None and (row.action, row.subject_id) in moments:
            row.created_at = moments[row.action, row.subject_id]
        elif row.action == "activity.status_changed" and row.subject_id in activities:
            row.created_at = activities[row.subject_id].status_changed_at

    # Demo activities are created with their status, so nobody has marked them done yet.
    for activity in ctx.activities:
        if activity.status is ActivityStatus.DONE and activity.completed_at is not None:
            db.add(
                GroupLog(
                    group_id=ctx.group.id,
                    actor_id=activity.owner_id or ctx.rng.choice(ctx.users).id,
                    action="activity.status_changed",
                    subject_type="activity",
                    subject_id=activity.id,
                    data={
                        "from": ActivityStatus.PLANNING.value,
                        "to": ActivityStatus.DONE.value,
                        "via": "status",
                    },
                    created_at=activity.completed_at,
                )
            )

    # Interest comes after an idea is added: at once for its creator, later for the others.
    for interest in db.scalars(
        select(ActivityInterest)
        .where(ActivityInterest.activity_id.in_(activities))
        .order_by(ActivityInterest.activity_id, ActivityInterest.user_id)
    ):
        activity = activities[interest.activity_id]
        if interest.user_id == activity.created_by_id:
            interest.created_at = activity.created_at
        else:
            interest.created_at = (
                activity.created_at + (ctx.now - activity.created_at) * ctx.rng.random() * 0.5
            )
