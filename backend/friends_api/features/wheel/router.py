import uuid
from typing import Annotated

from fastapi import APIRouter, Query
from fastapi import status as http_status

from friends_api.core.pagination import DEFAULT_LIMIT, CursorParam, LimitParam
from friends_api.core.schemas import ApiDate
from friends_api.deps import DbSession, GroupMember
from friends_api.features.activities.models import ActivityStatus
from friends_api.features.wheel import service
from friends_api.features.wheel.deps import SpinMember, WheelRng
from friends_api.features.wheel.schemas import (
    DEFAULT_WHEEL_STATUSES,
    MAX_FILTER_STATUSES,
    SpinCreate,
    WheelCandidates,
    WheelFilters,
    WheelSpin,
    WheelSpinPage,
)

router = APIRouter(tags=["wheel"])


@router.get("/groups/{group_id}/wheel/candidates")
def list_wheel_candidates(
    db: DbSession,
    access: GroupMember,
    # No default in the schema: the generated Dart client can't express an enum-list default,
    # so the server applies it when the key is omitted.
    status: Annotated[
        list[ActivityStatus] | None,
        Query(
            min_length=1,
            max_length=MAX_FILTER_STATUSES,
            description="Repeat the key for several. Omitted: idea and planning.",
        ),
    ] = None,
    category_id: uuid.UUID | None = None,
    include_subcategories: Annotated[
        bool, Query(description="With `category_id`: also its subcategories.")
    ] = True,
    interested_by: uuid.UUID | None = None,
    owner_id: uuid.UUID | None = None,
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
) -> WheelCandidates:
    """`WheelFilters` as query parameters: the pool's size and its first 50 activities, newest
    first."""
    filters = WheelFilters(
        status=status or list(DEFAULT_WHEEL_STATUSES),
        category_id=category_id,
        include_subcategories=include_subcategories,
        interested_by=interested_by,
        owner_id=owner_id,
        cost_max=cost_max,
        include_unpriced=include_unpriced,
        due_before=due_before,
    )
    return service.list_candidates(db, access, filters)


@router.post("/groups/{group_id}/wheel/spins", status_code=http_status.HTTP_201_CREATED)
def create_spin(body: SpinCreate, db: DbSession, access: GroupMember, rng: WheelRng) -> WheelSpin:
    """The server picks the result, every slice with the same weight. Without `activity_ids`
    the slices are the filtered pool (a random 50 when it is larger), newest first; with them,
    those activities in that order, and the filters are only stored."""
    spin = service.create_spin(db, access, body, rng=rng)
    db.commit()
    return service.to_spin(db, spin)


@router.get("/groups/{group_id}/wheel/spins")
def list_spins(
    db: DbSession,
    access: GroupMember,
    cursor: CursorParam = None,
    limit: LimitParam = DEFAULT_LIMIT,
) -> WheelSpinPage:
    """The spin history, newest first."""
    return service.list_spins(db, access, cursor=cursor, limit=limit)


@router.post("/wheel/spins/{spin_id}/accept")
def accept_spin(db: DbSession, access: SpinMember) -> WheelSpin:
    """Any member. An idea moves to planning; other statuses stay. Accepting again returns the
    spin unchanged."""
    service.accept_spin(db, access)
    return service.to_spin(db, access.spin)
