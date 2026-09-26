"""Loader for flat ``/events/{event_id}`` routes (contract section 7.1)."""

import uuid
from typing import Annotated

from fastapi import Depends

from friends_api.core.errors import NotFound
from friends_api.deps import CurrentUser, DbSession
from friends_api.features.events import service
from friends_api.features.events.service import EventAccess


def load_event(event_id: uuid.UUID, db: DbSession, user: CurrentUser) -> EventAccess:
    """The event plus the caller's membership in its group. A missing event and a non-member
    caller get the same 404."""
    access = service.get_access(db, event_id, user.id)
    if access is None:
        raise NotFound("No such event.")
    return access


EventMember = Annotated[EventAccess, Depends(load_event)]
