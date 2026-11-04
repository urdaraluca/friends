from fastapi import APIRouter, BackgroundTasks, Request, Response, status

from friends_api.core.mail import send_safely
from friends_api.core.ratelimit import limit_by_user
from friends_api.deps import (
    AppSettings,
    Auth,
    CurrentPrincipal,
    CurrentUser,
    DbSession,
    MailerDep,
)
from friends_api.features.auth import cookies, email_flows
from friends_api.features.auth import service as auth_service
from friends_api.features.auth.schemas import AccountDeletion, PasswordChange, TokenPair
from friends_api.features.availability import service as availability_service
from friends_api.features.availability.router import AvailabilityFrom, AvailabilityTo
from friends_api.features.availability.schemas import MyAvailability, MyAvailabilityUpdate
from friends_api.features.calendar_feed import service as calendar_feed_service
from friends_api.features.calendar_feed.schemas import CalendarFeed
from friends_api.features.events import calendar
from friends_api.features.events.params import FromParam, KindsParam, ToParam, TzParam
from friends_api.features.events.schemas import CalendarResponse
from friends_api.features.users import service
from friends_api.features.users.schemas import Me, MeUpdate, NotificationSettings

router = APIRouter(prefix="/me", tags=["users"])


@router.get("")
def get_me(user: CurrentUser) -> Me:
    return Me.from_user(user)


@router.put("")
def update_me(body: MeUpdate, db: DbSession, user: CurrentUser) -> Me:
    service.update_profile(db, user, body)
    return Me.from_user(user)


@router.post("/email-verification", status_code=status.HTTP_202_ACCEPTED)
def send_verification_email(
    db: DbSession,
    auth: Auth,
    user: CurrentUser,
    mailer: MailerDep,
    background: BackgroundTasks,
    request: Request,
) -> None:
    """Emails a new verification link (the older ones stop working). Nothing is sent when the
    address is already verified. At most 3 an hour."""
    limit_by_user(request, "verification_email", user.id)
    if email := email_flows.verification_email(db, auth, user):
        background.add_task(send_safely, mailer, email)


@router.get("/notifications")
def get_my_notifications(user: CurrentUser) -> NotificationSettings:
    return NotificationSettings.from_user(user)


@router.put("/notifications")
def update_my_notifications(
    body: NotificationSettings, db: DbSession, user: CurrentUser
) -> NotificationSettings:
    """Which notification emails I get. They go to a verified address only."""
    service.update_notifications(db, user, body)
    return NotificationSettings.from_user(user)


@router.post("/password")
def change_password(
    body: PasswordChange,
    db: DbSession,
    auth: Auth,
    principal: CurrentPrincipal,
    request: Request,
    response: Response,
) -> TokenPair:
    """Changes the password, signs out all other sessions and returns new tokens for this one."""
    tokens = auth_service.change_password(
        db,
        auth,
        principal.user,
        current_password=body.current_password,
        new_password=body.new_password,
        session_id=principal.claims.session_id,
    )
    return cookies.deliver(request, response, auth.settings, tokens)


@router.post("/deletion", status_code=status.HTTP_204_NO_CONTENT)
def delete_account(
    body: AccountDeletion,
    db: DbSession,
    auth: Auth,
    user: CurrentUser,
    request: Request,
    response: Response,
) -> None:
    """Deletes the account: owned groups go to the oldest admin (or member), or are deleted if
    you are alone in them; you leave every group; your profile is anonymized."""
    service.delete_account(db, auth, user, body.password)
    cookies.forget(request, response, auth.settings)


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


@router.get("/calendar-feed")
def get_my_calendar_feed(user: CurrentUser, settings: AppSettings) -> CalendarFeed:
    """My webcal subscription URLs, or nulls when the feed is off."""
    return calendar_feed_service.get_feed(settings, user)


@router.post("/calendar-feed")
def reset_my_calendar_feed(db: DbSession, user: CurrentUser, settings: AppSettings) -> CalendarFeed:
    """Turns the feed on, or gives it a new secret URL: the previous one stops working."""
    return calendar_feed_service.reset_feed(db, settings, user)


@router.delete("/calendar-feed", status_code=status.HTTP_204_NO_CONTENT)
def disable_my_calendar_feed(db: DbSession, user: CurrentUser) -> None:
    """Turns the feed off: its URL stops working."""
    calendar_feed_service.disable_feed(db, user)


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
