from typing import Annotated

from fastapi import APIRouter, Query

from friends_api.core.schemas import ApiDate
from friends_api.deps import DbSession, GroupMember
from friends_api.features.recap import service
from friends_api.features.recap.schemas import Recap, RecapPeriod

router = APIRouter(tags=["recap"])


@router.get("/groups/{group_id}/recap")
def get_group_recap(
    db: DbSession,
    access: GroupMember,
    period: RecapPeriod,
    start: Annotated[
        ApiDate | None,
        Query(
            description="The period's first day (the 1st of a month, or 1 January), in the "
            "group's timezone. Omitted: the current period."
        ),
    ] = None,
) -> Recap:
    """The group's highlights for a month or a year.

    Memories made, the most active planners, the top categories and a few extras.
    Only past and current periods, in the group's timezone."""
    return service.group_recap(db, access, period, start)
