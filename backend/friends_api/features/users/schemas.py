import calendar
import uuid
from datetime import date, datetime
from functools import cache
from typing import Annotated, Self
from zoneinfo import available_timezones

from pydantic import AfterValidator, BaseModel, Field, HttpUrl, StringConstraints, model_validator

from friends_api.core.schemas import RequestModel
from friends_api.features.auth.models import User

DisplayName = Annotated[str, StringConstraints(min_length=1, max_length=50)]


@cache
def _timezones() -> frozenset[str]:
    return frozenset(available_timezones())


def is_valid_timezone(name: str) -> bool:
    return name in _timezones()


def _check_timezone(name: str) -> str:
    if not is_valid_timezone(name):
        raise ValueError("unknown IANA timezone")
    return name


Timezone = Annotated[str, StringConstraints(max_length=64), AfterValidator(_check_timezone)]


class Birthday(BaseModel):
    month: int = Field(ge=1, le=12)
    day: int = Field(ge=1, le=31)
    year: int | None = Field(default=None, ge=1900)

    @model_validator(mode="after")
    def _check_day(self) -> Self:
        # Feb 29 is allowed without a year (it falls on Feb 28 in non-leap years).
        max_day = calendar.monthrange(self.year if self.year else 2000, self.month)[1]
        if self.day > max_day:
            raise ValueError("day is out of range for month")
        if self.year is not None and self.year > date.today().year:  # noqa: DTZ011
            raise ValueError("year is in the future")
        return self


class BirthdayPublic(BaseModel):
    month: int
    day: int


class UserPublic(BaseModel):
    id: uuid.UUID
    display_name: str
    avatar_url: str | None

    @classmethod
    def from_user(cls, user: User) -> UserPublic:
        return cls(id=user.id, display_name=user.display_name, avatar_url=user.avatar_url)


def user_birthday(user: User) -> Birthday | None:
    if user.birthday_month is None or user.birthday_day is None:
        return None
    return Birthday(month=user.birthday_month, day=user.birthday_day, year=user.birthday_year)


class Me(BaseModel):
    id: uuid.UUID
    email: str
    display_name: str
    avatar_url: str | None
    birthday: Birthday | None
    timezone: str
    locale: str | None
    created_at: datetime

    @classmethod
    def from_user(cls, user: User) -> Me:
        return cls(
            id=user.id,
            email=user.email,
            display_name=user.display_name,
            avatar_url=user.avatar_url,
            birthday=user_birthday(user),
            timezone=user.timezone,
            locale=user.locale,
            created_at=user.created_at,
        )


class MeUpdate(RequestModel):
    display_name: DisplayName
    birthday: Birthday | None = None
    timezone: Timezone
    locale: Annotated[str, StringConstraints(max_length=16)] | None = None
    avatar_url: HttpUrl | None = None
