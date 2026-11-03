from fastapi import APIRouter, Request, Response

from friends_api.core.db import utcnow
from friends_api.deps import DbSession
from friends_api.features.calendar_feed import service

router = APIRouter(tags=["calendar_feed"])


@router.api_route(
    "/calendar-feed/{token}.ics",
    methods=["GET", "HEAD"],
    include_in_schema=False,  # for calendar apps, not the client; no Authorization header
    response_class=Response,
)
def get_calendar_feed(token: str, db: DbSession, request: Request) -> Response:
    """My calendar as iCalendar (``text/calendar``), at the secret URL from
    ``GET /me/calendar-feed``. Unknown or revoked tokens are a 404."""
    user = service.feed_owner(db, token)
    request.state.user_id = str(user.id)  # for the access log
    return Response(
        content=service.render_feed(db, user, utcnow()),
        media_type="text/calendar; charset=utf-8",
        headers={"Content-Disposition": 'inline; filename="friends.ics"'},
    )
