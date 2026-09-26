"""Loaders for flat ``/polls/{poll_id}`` routes (contract section 7.1).

Routes under an activity (``/activities/{activity_id}/polls``) use ``ActivityMember``.
"""

import uuid
from typing import Annotated

from fastapi import Depends

from friends_api.core.errors import NotFound
from friends_api.deps import CurrentUser, DbSession
from friends_api.features.polls import service
from friends_api.features.polls.service import PollAccess, PollOptionAccess


def load_poll(poll_id: uuid.UUID, db: DbSession, user: CurrentUser) -> PollAccess:
    """The poll, its activity and the caller's membership in their group. A missing poll and a
    non-member caller get the same 404."""
    access = service.get_access(db, poll_id, user.id)
    if access is None:
        raise NotFound("No such poll.")
    return access


def load_poll_option(
    poll_id: uuid.UUID, option_id: uuid.UUID, db: DbSession, user: CurrentUser
) -> PollOptionAccess:
    """An option of the poll, with the same 404 for a missing poll or option and for a
    non-member caller."""
    target = service.get_option_access(db, poll_id, option_id, user.id)
    if target is None:
        raise NotFound("No such poll option.")
    return target


PollMember = Annotated[PollAccess, Depends(load_poll)]
PollOptionMember = Annotated[PollOptionAccess, Depends(load_poll_option)]
