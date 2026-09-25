from sqlalchemy.orm import Session

from friends_api.features.auth.models import User
from friends_api.features.users.schemas import MeUpdate


def update_profile(db: Session, user: User, body: MeUpdate) -> None:
    user.display_name = body.display_name
    user.timezone = body.timezone
    user.locale = body.locale
    user.avatar_url = str(body.avatar_url) if body.avatar_url else None
    user.birthday_month = body.birthday.month if body.birthday else None
    user.birthday_day = body.birthday.day if body.birthday else None
    user.birthday_year = body.birthday.year if body.birthday else None
    db.commit()
