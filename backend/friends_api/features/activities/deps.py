"""Loader for flat ``/activities/{activity_id}`` routes (contract section 7.1).

Other features with routes under an activity (polls: ``/activities/{activity_id}/polls``) reuse
``ActivityMember``.
"""

import uuid
from typing import Annotated

from fastapi import Depends

from friends_api.core.errors import NotFound
from friends_api.deps import CurrentUser, DbSession
from friends_api.features.activities import service
from friends_api.features.activities.service import ActivityAccess


def load_activity(activity_id: uuid.UUID, db: DbSession, user: CurrentUser) -> ActivityAccess:
    """The activity plus the caller's membership in its group. A missing activity and a
    non-member caller get the same 404."""
    access = service.get_access(db, activity_id, user.id)
    if access is None:
        raise NotFound("No such activity.")
    return access


ActivityMember = Annotated[ActivityAccess, Depends(load_activity)]
