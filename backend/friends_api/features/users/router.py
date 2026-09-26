from fastapi import APIRouter, status

from friends_api.deps import Auth, CurrentPrincipal, CurrentUser, DbSession
from friends_api.features.auth import service as auth_service
from friends_api.features.auth.schemas import AccountDeletion, PasswordChange, TokenPair
from friends_api.features.availability import service as availability_service
from friends_api.features.availability.router import AvailabilityFrom, AvailabilityTo
from friends_api.features.availability.schemas import MyAvailability, MyAvailabilityUpdate
from friends_api.features.events import calendar
from friends_api.features.events.params import FromParam, KindsParam, ToParam, TzParam
from friends_api.features.events.schemas import CalendarResponse
from friends_api.features.users import service
from friends_api.features.users.schemas import Me, MeUpdate

router = APIRouter(prefix="/me", tags=["users"])


@router.get("")
def get_me(user: CurrentUser) -> Me:
    return Me.from_user(user)


@router.put("")
def update_me(body: MeUpdate, db: DbSession, user: CurrentUser) -> Me:
    service.update_profile(db, user, body)
    return Me.from_user(user)


@router.post("/password")
def change_password(
    body: PasswordChange, db: DbSession, auth: Auth, principal: CurrentPrincipal
) -> TokenPair:
    """Changes the password, signs out all other sessions and returns new tokens for this one."""
    return auth_service.change_password(
        db,
        auth,
        principal.user,
        current_password=body.current_password,
        new_password=body.new_password,
        session_id=principal.claims.session_id,
    )


@router.post("/deletion", status_code=status.HTTP_204_NO_CONTENT)
def delete_account(body: AccountDeletion, db: DbSession, auth: Auth, user: CurrentUser) -> None:
    """Deletes the account: owned groups go to the oldest admin (or member), or are deleted if
    you are alone in them; you leave every group; your profile is anonymized."""
    service.delete_account(db, auth, user, body.password)


@router.get("/calendar")
def get_my_calendar(
    db: DbSession,
    user: CurrentUser,
    from_: FromParam,
    to: ToParam,
    tz: TzParam = None,
    kinds: KindsParam = None,
) -> CalendarResponse:
    """Occurrences across all your groups in ``[from, to)``. Member birthdays appear once per
    person (``group_id`` null) if they show them in at least one group you share."""
    query = calendar.CalendarQuery(from_date=from_, to_date=to, tz=tz, kinds=kinds)
    return calendar.my_calendar(db, user, query)


@router.get("/availability")
def get_my_availability(
    db: DbSession, user: CurrentUser, from_: AvailabilityFrom, to: AvailabilityTo
) -> MyAvailability:
    """My answers in ``[from, to)`` (at most 92 days), by date then slot. They show in every group
    I'm in."""
    return availability_service.my_availability(db, user, from_, to)


@router.put("/availability")
def update_my_availability(
    body: MyAvailabilityUpdate, db: DbSession, user: CurrentUser
) -> MyAvailability:
    """Replaces my answers in ``[from_date, to_date)``: a slot left out becomes unknown."""
    return availability_service.update_my_availability(db, user, body)
