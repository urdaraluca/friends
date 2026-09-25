import uuid

import jwt
import pytest

from friends_api.core.config import AppEnv, Settings
from friends_api.core.errors import AuthError
from friends_api.core.security import (
    Passwords,
    create_access_token,
    decode_access_token,
    hash_refresh_token,
    new_refresh_token,
)
from tests.conftest import FAST_ARGON2


@pytest.fixture
def settings() -> Settings:
    return Settings(_env_file=None, app_env=AppEnv.TEST, **FAST_ARGON2)


def test_passwords_hash_and_verify(settings: Settings) -> None:
    passwords = Passwords(settings)
    hashed = passwords.hash("correct horse battery")

    assert hashed.startswith("$argon2id$")
    assert passwords.verify(hashed, "correct horse battery")
    assert not passwords.verify(hashed, "wrong horse battery")
    assert not passwords.verify(None, "correct horse battery")
    assert not passwords.verify("not-a-hash", "correct horse battery")


def test_hashes_are_upgraded_when_parameters_change(settings: Settings) -> None:
    old = Passwords(settings).hash("correct horse battery")
    stronger = Passwords(settings.model_copy(update={"argon2_time_cost": 2}))

    assert stronger.needs_rehash(old)
    assert stronger.verify(old, "correct horse battery")


def test_access_tokens_round_trip(settings: Settings) -> None:
    user_id, session_id = uuid.uuid7(), uuid.uuid7()
    token, ttl = create_access_token(
        settings, user_id=user_id, session_id=session_id, token_version=3
    )

    claims = decode_access_token(settings, token)

    assert ttl == 15 * 60
    assert (claims.user_id, claims.session_id, claims.token_version) == (user_id, session_id, 3)


def test_tokens_signed_with_another_secret_are_rejected(settings: Settings) -> None:
    other = settings.model_copy(update={"jwt_secret": "another-secret-another-secret-another"})
    token, _ = create_access_token(
        other, user_id=uuid.uuid7(), session_id=uuid.uuid7(), token_version=0
    )

    with pytest.raises(AuthError) as exc_info:
        decode_access_token(settings, token)
    assert exc_info.value.code == "unauthenticated"


def test_tokens_for_another_audience_or_type_are_rejected(settings: Settings) -> None:
    base = {"sub": str(uuid.uuid7()), "sid": str(uuid.uuid7()), "tv": 0, "iat": 0, "exp": 2**40}
    wrong_audience = jwt.encode(
        {**base, "typ": "access", "iss": "friends-api", "aud": "someone-else"},
        settings.jwt_secret,
        algorithm="HS256",
    )
    wrong_type = jwt.encode(
        {**base, "typ": "refresh", "iss": "friends-api", "aud": "friends-app"},
        settings.jwt_secret,
        algorithm="HS256",
    )

    for token in (wrong_audience, wrong_type):
        with pytest.raises(AuthError):
            decode_access_token(settings, token)


def test_refresh_tokens_are_random_and_stored_hashed() -> None:
    token, digest = new_refresh_token()
    other, _ = new_refresh_token()

    assert token != other
    assert len(token) >= 43
    assert digest == hash_refresh_token(token)
    assert len(digest) == 64
    assert token not in digest
