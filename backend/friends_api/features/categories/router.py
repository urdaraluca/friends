from fastapi import APIRouter, status

from friends_api.deps import DbSession, GroupMember
from friends_api.features.categories import service
from friends_api.features.categories.deps import CategoryMember
from friends_api.features.categories.schemas import (
    Category,
    CategoryNode,
    CategoryOrder,
    CategoryWrite,
)

router = APIRouter(tags=["categories"])


@router.get("/groups/{group_id}/categories")
def list_categories(db: DbSession, access: GroupMember) -> list[CategoryNode]:
    """Top-level categories by position, then name; each with its subcategories in the same
    order."""
    return service.list_categories(db, access)


@router.post("/groups/{group_id}/categories", status_code=status.HTTP_201_CREATED)
def create_category(body: CategoryWrite, db: DbSession, access: GroupMember) -> Category:
    """Any member. ``position: null`` appends at the end among the siblings."""
    category = service.create_category(db, access, body)
    db.commit()
    return service.to_category(db, category, access.membership)


@router.put("/groups/{group_id}/categories/order")
def reorder_categories(
    body: CategoryOrder, db: DbSession, access: GroupMember
) -> list[CategoryNode]:
    """Admins. Orders the top-level categories, or one category's subcategories.
    ``category_ids`` lists every one of them, exactly once. Returns the whole tree."""
    service.reorder_categories(db, access, body)
    return service.list_categories(db, access)


@router.put("/categories/{category_id}")
def update_category(body: CategoryWrite, db: DbSession, access: CategoryMember) -> Category:
    """The creator or an admin. ``position: null`` keeps the current position; a field's type
    can't change (remove it and add it back)."""
    service.update_category(db, access, body)
    return service.to_category(db, access.category, access.membership)


@router.delete("/categories/{category_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_category(db: DbSession, access: CategoryMember) -> None:
    """The creator or an admin. A subcategory's activities move to its parent; deleting a
    top-level category deletes its subcategories and leaves their activities uncategorized."""
    service.delete_category(db, access)
