from typing import Annotated

from fastapi import APIRouter, Query

from friends_api.core.schemas import ApiDate
from friends_api.deps import DbSession, GroupMember
from friends_api.features.availability import service
from friends_api.features.availability.schemas import GroupAvailability

router = APIRouter(tags=["availability"])

AvailabilityFrom = Annotated[ApiDate, Query(alias="from", description="First day (inclusive).")]
AvailabilityTo = Annotated[
    ApiDate, Query(alias="to", description="Last day (exclusive); at most 92 days after `from`.")
]


@router.get("/groups/{group_id}/availability")
def get_group_availability(
    db: DbSession, access: GroupMember, from_: AvailabilityFrom, to: AvailabilityTo
) -> GroupAvailability:
    """The current members' availability per day and slot in ``[from, to)``, and the best days
    (score = free + 0.5 * maybe, then fewer busy, then the earliest). Who is free or maybe is
    listed by name; busy is a count only."""
    return service.group_availability(db, access, from_, to)
