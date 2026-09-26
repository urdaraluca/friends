"""Batched user lookups for responses that show people (owners, creators, voters, ...).

Load every user a page needs in one query, then build ``UserPublic`` values from the map.
"""

import uuid
from collections.abc import Iterable, Mapping

from sqlalchemy import select
from sqlalchemy.orm import Session

from friends_api.features.auth.models import User
from friends_api.features.users.schemas import UserPublic


def users_by_id(db: Session, ids: Iterable[uuid.UUID | None]) -> dict[uuid.UUID, User]:
    wanted = {user_id for user_id in ids if user_id is not None}
    if not wanted:
        return {}
    return {user.id: user for user in db.scalars(select(User).where(User.id.in_(wanted)))}


def public_user(users: Mapping[uuid.UUID, User], user_id: uuid.UUID | None) -> UserPublic | None:
    user = users.get(user_id) if user_id is not None else None
    return UserPublic.from_user(user) if user is not None else None
