"""Calendar values shown on activities: ``ActivitySummary.next_occurrence`` and
``Activity.events`` (contract section 9).

Batched: one query per page of activities, never one per row.
"""

import uuid
from collections.abc import Sequence
from datetime import datetime

from sqlalchemy.orm import Session

from friends_api.features.activities.models import Activity
from friends_api.features.events.schemas import EventRef, OccurrenceRef


def next_occurrences(
    db: Session, activities: Sequence[Activity], *, now: datetime
) -> dict[uuid.UUID, OccurrenceRef]:
    """The next occurrence (at or after ``now``) of each activity's linked events, by activity
    ID; activities without one are left out.

    TODO(#12): events don't exist yet, so no activity has one. Load the linked events of all
    ``activities`` in one query and expand them with ``events.recurrence``.
    """
    return {}


def linked_events(db: Session, activity: Activity) -> list[EventRef]:
    """The activity's linked events, by ``window_start``.

    TODO(#12): events don't exist yet; select the events whose ``activity_id`` is this one.
    """
    return []
