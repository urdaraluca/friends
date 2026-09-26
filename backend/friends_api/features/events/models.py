"""Calendar events (contract sections 3.1 and 5).

M6 only defines ``EventKind``, because the activity responses already reference events
(``Activity.events``, ``ActivitySummary.next_occurrence``). TODO(#12): add the ``events`` and
``event_exceptions`` tables here and import this module in ``friends_api/db_models.py``.
"""

from enum import StrEnum


class EventKind(StrEnum):
    ONE_TIME = "one_time"
    RECURRING = "recurring"
    BIRTHDAY = "birthday"
