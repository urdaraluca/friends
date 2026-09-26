"""Poll counters on activity cards (contract section 9, "Derived counters").

One batched query per page of activities, never one per row.
"""

import uuid
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import datetime

from sqlalchemy import and_, case, exists, func, select
from sqlalchemy.orm import Session

from friends_api.features.polls.models import Poll, PollVote


@dataclass(frozen=True, slots=True)
class PollCounters:
    poll_count: int = 0
    """All polls of the activity."""
    open_poll_count: int = 0
    """Open polls: ``closed_at IS NULL AND (closes_at IS NULL OR closes_at > now)``."""
    my_unvoted_poll_count: int = 0
    """Open polls where the caller has no vote (the card's "Vote" badge)."""


NO_POLLS = PollCounters()


def poll_counters(
    db: Session, activity_ids: Sequence[uuid.UUID], user_id: uuid.UUID, *, now: datetime
) -> dict[uuid.UUID, PollCounters]:
    """Counters by activity ID; activities without polls are left out (``NO_POLLS``)."""
    is_open = Poll.open_clause(now)
    voted = exists().where(PollVote.poll_id == Poll.id, PollVote.user_id == user_id)
    rows = db.execute(
        select(
            Poll.activity_id,
            func.count(),
            func.sum(case((is_open, 1), else_=0)),
            func.sum(case((and_(is_open, ~voted), 1), else_=0)),
        )
        .where(Poll.activity_id.in_(activity_ids))
        .group_by(Poll.activity_id)
    ).tuples()
    return {
        activity_id: PollCounters(
            poll_count=total, open_poll_count=open_count, my_unvoted_poll_count=unvoted
        )
        for activity_id, total, open_count, unvoted in rows
    }
