from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, EmailStr, Field, StringConstraints

from friends_api.features.users.schemas import DisplayName, Me

Password = Annotated[str, StringConstraints(min_length=10, max_length=128)]
DeviceLabel = Annotated[str, StringConstraints(strip_whitespace=True, max_length=100)]


class RegisterRequest(BaseModel):
    email: EmailStr
    password: Password
    display_name: DisplayName
    timezone: Annotated[str, StringConstraints(max_length=64)] | None = None
    """IANA name from the device; unknown values fall back to UTC."""
    device_label: DeviceLabel | None = None


class LoginRequest(BaseModel):
    email: EmailStr
    password: Annotated[str, StringConstraints(max_length=128)]
    device_label: DeviceLabel | None = None


class RefreshRequest(BaseModel):
    refresh_token: Annotated[str, StringConstraints(min_length=1, max_length=200)]


class LogoutRequest(BaseModel):
    refresh_token: Annotated[str, StringConstraints(min_length=1, max_length=200)]


class ChangePasswordRequest(BaseModel):
    current_password: Annotated[str, StringConstraints(max_length=128)]
    new_password: Password


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: Literal["bearer"] = "bearer"  # noqa: S105 - OAuth token type, not a secret
    access_expires_in: int = Field(description="Access token lifetime in seconds.")
    refresh_expires_at: datetime


class AuthSession(BaseModel):
    user: Me
    tokens: TokenPair
