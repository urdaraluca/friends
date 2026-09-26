"""Loader for flat ``/categories/{category_id}`` routes (contract section 7.1)."""

import uuid
from typing import Annotated

from fastapi import Depends

from friends_api.core.errors import NotFound
from friends_api.deps import CurrentUser, DbSession
from friends_api.features.categories import service
from friends_api.features.categories.service import CategoryAccess


def load_category(category_id: uuid.UUID, db: DbSession, user: CurrentUser) -> CategoryAccess:
    """The category plus the caller's membership in its group. A missing category and a
    non-member caller get the same 404."""
    access = service.get_access(db, category_id, user.id)
    if access is None:
        raise NotFound("No such category.")
    return access


CategoryMember = Annotated[CategoryAccess, Depends(load_category)]
