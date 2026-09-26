import uuid

from fastapi import APIRouter
from fastapi import status as http_status

from friends_api.deps import CurrentUser, DbSession, GroupMember
from friends_api.features.events import calendar, service
from friends_api.features.events.deps import EventMember
from friends_api.features.events.params import FromParam, KindsParam, ToParam, TzParam
from friends_api.features.events.schemas import CalendarResponse, Event, EventUpdate, EventWrite

router = APIRouter(tags=["events"])


@router.get("/groups/{group_id}/calendar")
def get_group_calendar(
    db: DbSession,
    access: GroupMember,
    user: CurrentUser,
    from_: FromParam,
    to: ToParam,
    tz: TzParam = None,
    kinds: KindsParam = None,
    category_id: uuid.UUID | None = None,
) -> CalendarResponse:
    """Occurrences in ``[from, to)``, sorted: by local start date in ``tz``, all-day before
    timed, then start, title and key. ``category_id`` also matches its subcategories and leaves
    member birthdays out."""
    query = calendar.CalendarQuery(
        from_date=from_, to_date=to, tz=tz, kinds=kinds, category_id=category_id
    )
    return calendar.group_calendar(db, access, user, query)


@router.post("/groups/{group_id}/events", status_code=http_status.HTTP_201_CREATED)
def create_event(body: EventWrite, db: DbSession, access: GroupMember) -> Event:
    """Any member. Linking an activity in ``idea`` or ``planning`` makes it ``scheduled``."""
    event = service.create_event(db, access, body)
    db.commit()
    return service.to_event(db, service.EventAccess(event=event, membership=access.membership))


@router.get("/events/{event_id}")
def get_event(db: DbSession, access: EventMember) -> Event:
    """The series definition, with its cancelled occurrence keys."""
    return service.to_event(db, access)


@router.put("/events/{event_id}")
def update_event(body: EventUpdate, db: DbSession, access: EventMember) -> Event:
    """Edits the whole series; send the ``version`` you last read. Changing the start, the
    all-day flag, the timezone or the rule restores every cancelled occurrence. The creator,
    the linked activity's owner or an admin."""
    service.update_event(db, access, body)
    return service.to_event(db, access)


@router.delete("/events/{event_id}", status_code=http_status.HTTP_204_NO_CONTENT)
def delete_event(db: DbSession, access: EventMember) -> None:
    """The whole series. The creator, the linked activity's owner or an admin."""
    service.delete_event(db, access)


@router.delete(
    "/events/{event_id}/occurrences/{occurrence_key}",
    status_code=http_status.HTTP_204_NO_CONTENT,
)
def cancel_occurrence(db: DbSession, access: EventMember, occurrence_key: str) -> None:
    """Cancels one occurrence (idempotent). ``occurrence_key``: ``YYYYMMDDTHHMMSSZ`` (timed) or
    ``YYYYMMDD`` (all-day, birthdays). Not for one-time events: delete the event instead."""
    service.cancel_occurrence(db, access, occurrence_key)


@router.post(
    "/events/{event_id}/occurrences/{occurrence_key}/restore",
    status_code=http_status.HTTP_204_NO_CONTENT,
)
def restore_occurrence(db: DbSession, access: EventMember, occurrence_key: str) -> None:
    """Restores a cancelled occurrence (idempotent)."""
    service.restore_occurrence(db, access, occurrence_key)
