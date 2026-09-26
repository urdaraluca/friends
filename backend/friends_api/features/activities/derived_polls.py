"""Poll counters on activity cards (contract section 9, "Derived counters").

One batched query per page of activities, never one per row.
"""

import uuid
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import datetime

from sqlalchemy.orm import Session


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
    """Counters by activity ID; activities without polls may be left out (``NO_POLLS``).

    TODO(#10): polls don't exist yet, so every activity has none. Replace this body with one
    grouped query over ``polls`` (and ``poll_votes`` for the caller) for ``activity_ids``.
    """
    return {}
