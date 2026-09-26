"""Activity permissions (contract section 7.2); they also compute the ``can_*`` flags.

Any member may create an activity, edit its content (PUT), change its status and toggle their
own interest.
"""

import uuid

from friends_api.features.activities.models import Activity
from friends_api.features.groups.models import Membership


def can_edit_activity(actor: Membership, activity: Activity) -> bool:
    """Content is editable by every member (an owner change has its own rule)."""
    return True


def can_delete_activity(actor: Membership, activity: Activity) -> bool:
    return actor.is_admin or actor.user_id in (activity.created_by_id, activity.owner_id)


def can_change_owner(actor: Membership, activity: Activity, new_owner_id: uuid.UUID | None) -> bool:
    """A member may claim an unowned activity (set it to themselves); the current owner may hand
    it to anyone or to nobody; an admin+ may do anything."""
    if new_owner_id == activity.owner_id or actor.is_admin:
        return True
    if activity.owner_id == actor.user_id:
        return True
    return activity.owner_id is None and new_owner_id == actor.user_id
