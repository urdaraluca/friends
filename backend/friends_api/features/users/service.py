from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from friends_api.core.db import utcnow
from friends_api.features.auth.models import DELETED_USER_NAME, EmailToken, RefreshToken, User
from friends_api.features.auth.service import AuthContext, check_current_password
from friends_api.features.groups import service as groups_service
from friends_api.features.groups.models import Membership
from friends_api.features.users.schemas import MeUpdate, NotificationSettings


def update_profile(db: Session, user: User, body: MeUpdate) -> None:
    user.display_name = body.display_name
    user.timezone = body.timezone
    user.locale = body.locale
    user.avatar_url = str(body.avatar_url) if body.avatar_url else None
    user.birthday_month = body.birthday.month if body.birthday else None
    user.birthday_day = body.birthday.day if body.birthday else None
    user.birthday_year = body.birthday.year if body.birthday else None
    db.commit()


def update_notifications(db: Session, user: User, body: NotificationSettings) -> None:
    user.notify_polls = body.polls
    user.notify_wheel = body.wheel
    user.notify_reminders = body.reminders
    db.commit()


def delete_account(db: Session, ctx: AuthContext, user: User, password: str) -> None:
    """Contract section 4.8: hand over or delete owned groups, leave every group, anonymize.

    The row is kept so authored content still shows "Deleted user".
    """
    check_current_password(ctx, user, password, "password")
    groups_service.transfer_or_delete_owned_groups(db, user)
    for membership in db.scalars(select(Membership).where(Membership.user_id == user.id)).all():
        groups_service.end_membership(
            db,
            membership,
            actor_id=user.id,
            action="member.left",
            data={"reason": "account_deleted"},
        )
    user.email = f"deleted-{user.id}@invalid"
    user.password_hash = None
    user.display_name = DELETED_USER_NAME
    user.avatar_url = None
    user.birthday_month = user.birthday_day = user.birthday_year = None
    user.locale = None
    user.timezone = "UTC"
    user.deleted_at = utcnow()
    user.token_version += 1
    user.calendar_feed_token = None
    user.email_verified_at = None
    db.execute(delete(EmailToken).where(EmailToken.user_id == user.id))
    db.execute(delete(RefreshToken).where(RefreshToken.user_id == user.id))
    db.commit()
