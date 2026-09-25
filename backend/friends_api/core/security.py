"""Password hashing, access tokens (JWT) and refresh tokens (opaque, stored hashed)."""

import hashlib
import secrets
import threading
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError

from friends_api.core.config import Settings
from friends_api.core.errors import AuthError

JWT_ALGORITHM = "HS256"
JWT_ISSUER = "friends-api"
JWT_AUDIENCE = "friends-app"
JWT_LEEWAY_SECONDS = 30


class Passwords:
    """argon2id hashing.

    Hashing a password takes ~64 MiB and a few hundred ms on a Pi, so at most two run at once
    (a burst of logins would otherwise need gigabytes of RAM). argon2 releases the GIL.
    """

    def __init__(self, settings: Settings, max_concurrent: int = 2) -> None:
        self._hasher = PasswordHasher(
            time_cost=settings.argon2_time_cost,
            memory_cost=settings.argon2_memory_kib,
            parallelism=settings.argon2_parallelism,
        )
        self._slots = threading.BoundedSemaphore(max_concurrent)
        # Verified against when the email is unknown, so timing doesn't reveal which emails exist.
        self._dummy_hash = self.hash(secrets.token_urlsafe(16))

    def hash(self, password: str) -> str:
        with self._slots:
            return self._hasher.hash(password)

    def verify(self, password_hash: str | None, password: str) -> bool:
        with self._slots:
            try:
                return self._hasher.verify(password_hash or self._dummy_hash, password) and (
                    password_hash is not None
                )
            except VerifyMismatchError, VerificationError, InvalidHashError:
                return False

    def needs_rehash(self, password_hash: str) -> bool:
        return self._hasher.check_needs_rehash(password_hash)


@dataclass(frozen=True, slots=True)
class AccessClaims:
    user_id: uuid.UUID
    session_id: uuid.UUID
    token_version: int


def create_access_token(
    settings: Settings, *, user_id: uuid.UUID, session_id: uuid.UUID, token_version: int
) -> tuple[str, int]:
    """Returns the signed JWT and its lifetime in seconds."""
    now = datetime.now(UTC)
    ttl = timedelta(minutes=settings.access_token_ttl_minutes)
    payload = {
        "sub": str(user_id),
        "sid": str(session_id),
        "tv": token_version,
        "typ": "access",
        "iss": JWT_ISSUER,
        "aud": JWT_AUDIENCE,
        "iat": int(now.timestamp()),
        "exp": int((now + ttl).timestamp()),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=JWT_ALGORITHM), int(
        ttl.total_seconds()
    )


def decode_access_token(settings: Settings, token: str) -> AccessClaims:
    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret,
            algorithms=[JWT_ALGORITHM],
            audience=JWT_AUDIENCE,
            issuer=JWT_ISSUER,
            leeway=JWT_LEEWAY_SECONDS,
            options={"require": ["sub", "sid", "tv", "typ", "exp", "iat"]},
        )
    except jwt.ExpiredSignatureError as exc:
        raise AuthError("Access token expired.", code="token_expired") from exc
    except jwt.InvalidTokenError as exc:
        raise AuthError("Invalid access token.") from exc
    if payload["typ"] != "access":
        raise AuthError("Invalid access token.")
    try:
        return AccessClaims(
            user_id=uuid.UUID(payload["sub"]),
            session_id=uuid.UUID(payload["sid"]),
            token_version=int(payload["tv"]),
        )
    except (TypeError, ValueError) as exc:
        raise AuthError("Invalid access token.") from exc


def new_refresh_token() -> tuple[str, str]:
    """Returns (token for the client, sha256 hex digest to store)."""
    token = secrets.token_urlsafe(32)
    return token, hash_refresh_token(token)


def hash_refresh_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()
