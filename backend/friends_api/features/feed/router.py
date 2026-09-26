from fastapi import APIRouter

from friends_api.core.pagination import DEFAULT_LIMIT, CursorParam, LimitParam
from friends_api.deps import DbSession, GroupMember
from friends_api.features.feed import service
from friends_api.features.feed.schemas import FeedPage

router = APIRouter(tags=["feed"])


@router.get("/groups/{group_id}/feed")
def list_group_feed(
    db: DbSession,
    access: GroupMember,
    cursor: CursorParam = None,
    limit: LimitParam = DEFAULT_LIMIT,
) -> FeedPage:
    """What happened in the group, newest first: ideas, events, polls, the wheel and members."""
    return service.group_feed(db, access, cursor=cursor, limit=limit)
