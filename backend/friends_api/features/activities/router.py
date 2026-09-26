import uuid
from typing import Annotated

from fastapi import APIRouter, Query
from fastapi import status as http_status

from friends_api.core.pagination import DEFAULT_LIMIT, CursorParam, LimitParam
from friends_api.core.schemas import ApiDate
from friends_api.deps import DbSession, GroupMember
from friends_api.features.activities import service
from friends_api.features.activities.deps import ActivityMember
from friends_api.features.activities.filters import DEFAULT_STATUSES, ActivityFilters
from friends_api.features.activities.models import ActivityStatus
from friends_api.features.activities.schemas import (
    Activity,
    ActivityCreate,
    ActivityPage,
    ActivitySort,
    ActivityUpdate,
    InterestState,
    SortOrder,
    StatusChange,
)

router = APIRouter(tags=["activities"])

_DEFAULT_STATUS_LIST = list(DEFAULT_STATUSES)


@router.get("/groups/{group_id}/activities")
def list_activities(
    db: DbSession,
    access: GroupMember,
    status: Annotated[
        list[ActivityStatus],
        Query(description="Repeat the key for several; done and dropped are the archive."),
    ] = _DEFAULT_STATUS_LIST,
    category_id: uuid.UUID | None = None,
    include_subcategories: Annotated[
        bool, Query(description="With `category_id`: also its subcategories.")
    ] = True,
    owner_id: uuid.UUID | None = None,
    interested_by: uuid.UUID | None = None,
    cost_max: Annotated[
        int | None,
        Query(ge=0, description="`estimated_cost <= cost_max` in the group's currency."),
    ] = None,
    include_unpriced: Annotated[
        bool,
        Query(
            description="With `cost_max`: also activities without a cost or in another currency."
        ),
    ] = True,
    due_before: Annotated[
        ApiDate | None, Query(description="`due_date <= due_before` (inclusive).")
    ] = None,
    q: Annotated[
        str | None,
        Query(min_length=1, max_length=100, description="Case-insensitive title substring."),
    ] = None,
    sort: ActivitySort = ActivitySort.CREATED_AT,
    order: SortOrder = SortOrder.DESC,
    cursor: CursorParam = None,
    limit: LimitParam = DEFAULT_LIMIT,
) -> ActivityPage:
    """The backlog, cursor-paginated. Due date and cost sort with nulls last; ties are broken
    by id (descending)."""
    filters = ActivityFilters(
        statuses=status,
        category_id=category_id,
        include_subcategories=include_subcategories,
        owner_id=owner_id,
        interested_by=interested_by,
        cost_max=cost_max,
        include_unpriced=include_unpriced,
        due_before=due_before,
        q=q,
    )
    return service.list_activities(
        db, access, filters, sort=sort, order=order, cursor=cursor, limit=limit
    )


@router.post("/groups/{group_id}/activities", status_code=http_status.HTTP_201_CREATED)
def create_activity(body: ActivityCreate, db: DbSession, access: GroupMember) -> Activity:
    """The creator is marked interested. ``owner_id: null`` means the creator."""
    activity = service.create_activity(db, access, body)
    db.commit()
    return service.to_activity(
        db, service.ActivityAccess(activity=activity, membership=access.membership)
    )


@router.get("/activities/{activity_id}")
def get_activity(db: DbSession, access: ActivityMember) -> Activity:
    return service.to_activity(db, access)


@router.put("/activities/{activity_id}")
def update_activity(body: ActivityUpdate, db: DbSession, access: ActivityMember) -> Activity:
    """Replaces the content; send the ``version`` you last read. ``owner_id: null`` means
    unowned. A member may claim an unowned activity, the owner may hand it to anyone or to
    nobody, and admins may do anything."""
    service.update_activity(db, access, body)
    return service.to_activity(db, access)


@router.delete("/activities/{activity_id}", status_code=http_status.HTTP_204_NO_CONTENT)
def delete_activity(db: DbSession, access: ActivityMember) -> None:
    """The creator, the owner or an admin."""
    service.delete_activity(db, access)


@router.post("/activities/{activity_id}/status")
def set_activity_status(body: StatusChange, db: DbSession, access: ActivityMember) -> Activity:
    """Any transition is allowed; the same status changes nothing."""
    service.set_activity_status(db, access, body.status)
    return service.to_activity(db, access)


@router.put("/activities/{activity_id}/interest")
def add_interest(db: DbSession, access: ActivityMember) -> InterestState:
    """Marks the caller as interested (idempotent)."""
    service.add_interest(db, access)
    return service.interest_state(db, access)


@router.delete("/activities/{activity_id}/interest")
def remove_interest(db: DbSession, access: ActivityMember) -> InterestState:
    """Removes the caller's interest (idempotent)."""
    service.remove_interest(db, access)
    return service.interest_state(db, access)
