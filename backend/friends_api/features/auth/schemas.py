from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, EmailStr, Field, StringConstraints

from friends_api.core.schemas import RequestModel
from friends_api.features.users.schemas import DisplayName, Me

Password = Annotated[str, StringConstraints(min_length=10, max_length=128)]
AnyPassword = Annotated[str, StringConstraints(min_length=1, max_length=128)]
DeviceLabel = Annotated[str, StringConstraints(max_length=100)]


class RegisterRequest(RequestModel):
    email: Annotated[EmailStr, StringConstraints(max_length=254)]
    password: Password
    display_name: DisplayName
    timezone: Annotated[str, StringConstraints(max_length=64)] | None = None
    """IANA name from the device; unknown values fall back to UTC."""
    device_label: DeviceLabel | None = None
    invite_code: Annotated[str, StringConstraints(max_length=32)] | None = None
    """Required when REGISTRATION_MODE=invite_only; joins that group."""


class LoginRequest(RequestModel):
    email: Annotated[EmailStr, StringConstraints(max_length=254)]
    password: AnyPassword
    device_label: DeviceLabel | None = None


class RefreshRequest(RequestModel):
    """Also the body of /auth/logout."""

    refresh_token: Annotated[str, StringConstraints(min_length=1, max_length=128)]


class PasswordChange(RequestModel):
    current_password: AnyPassword
    new_password: Password


class AccountDeletion(RequestModel):
    password: AnyPassword


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: Literal["bearer"] = "bearer"  # noqa: S105 - OAuth token type, not a secret
    access_expires_in: int = Field(description="Access token lifetime in seconds.")
    refresh_expires_at: datetime


class AuthSession(BaseModel):
    user: Me
    tokens: TokenPair
