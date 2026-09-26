"""Event permissions (contract section 7.2); they also compute the ``can_*`` flags.

Any member may create an event. Editing or deleting one, and cancelling or restoring an
occurrence, is for its creator, the owner of its linked activity, or an admin+.
"""

import uuid

from friends_api.features.events.models import Event
from friends_api.features.groups.models import Membership


def can_edit_event(actor: Membership, event: Event, activity_owner_id: uuid.UUID | None) -> bool:
    """``activity_owner_id``: the owner of the event's linked activity, if any."""
    if actor.is_admin or actor.user_id == event.created_by_id:
        return True
    return activity_owner_id is not None and actor.user_id == activity_owner_id


def can_delete_event(actor: Membership, event: Event, activity_owner_id: uuid.UUID | None) -> bool:
    return can_edit_event(actor, event, activity_owner_id)
