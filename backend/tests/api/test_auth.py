from datetime import UTC, datetime, timedelta
from typing import Any

import time_machine
from fastapi.testclient import TestClient

from tests.factories import DEFAULT_PASSWORD, bearer, login, register

NOW = datetime(2026, 10, 1, 12, 0, tzinfo=UTC)


def refresh(client: TestClient, token: str) -> Any:
    return client.post("/api/v1/auth/refresh", json={"refresh_token": token})


# --- registration -------------------------------------------------------------------------


def test_register_returns_the_user_and_a_session(client: TestClient) -> None:
    response = client.post(
        "/api/v1/auth/register",
        json={
            "email": "  Ana@Example.COM ",
            "password": DEFAULT_PASSWORD,
            "display_name": "  Ana ",
            "timezone": "Europe/Bucharest",
            "device_label": "android",
        },
    )

    assert response.status_code == 201
    body = response.json()
    assert body["user"]["email"] == "ana@example.com"
    assert body["user"]["display_name"] == "Ana"
    assert body["user"]["timezone"] == "Europe/Bucharest"
    assert body["tokens"]["token_type"] == "bearer"
    assert body["tokens"]["access_expires_in"] == 15 * 60
    me = client.get("/api/v1/me", headers=bearer(body["tokens"]["access_token"]))
    assert me.json()["email"] == "ana@example.com"


def test_register_falls_back_to_utc_for_unknown_timezones(client: TestClient) -> None:
    account = register(client, timezone="Mars/Olympus_Mons")

    assert account.body["user"]["timezone"] == "UTC"


def test_register_rejects_duplicate_emails_case_insensitively(client: TestClient) -> None:
    register(client, email="dup@example.com")

    response = client.post(
        "/api/v1/auth/register",
        json={"email": "DUP@example.com", "password": DEFAULT_PASSWORD, "display_name": "X"},
    )

    assert response.status_code == 409
    assert response.json()["code"] == "email_taken"


def test_register_rejects_weak_passwords_without_echoing_them(client: TestClient) -> None:
    too_short = client.post(
        "/api/v1/auth/register",
        json={"email": "a@example.com", "password": "hunter2", "display_name": "A"},
    )
    same_as_email = client.post(
        "/api/v1/auth/register",
        json={"email": "b.user@example.com", "password": "B.User@Example.com", "display_name": "B"},
    )

    assert too_short.status_code == 422
    assert too_short.json()["errors"][0]["field"] == "password"
    assert "hunter2" not in too_short.text
    assert same_as_email.status_code == 422
    assert same_as_email.json()["code"] == "weak_password"


# --- login ----------------------------------------------------------------------------------


def test_login_is_case_insensitive_on_email(client: TestClient) -> None:
    register(client, email="case@example.com")

    body = login(client, "CASE@Example.com")

    assert body["user"]["email"] == "case@example.com"


def test_wrong_password_and_unknown_email_look_the_same(client: TestClient) -> None:
    register(client, email="known@example.com")

    wrong = client.post(
        "/api/v1/auth/login", json={"email": "known@example.com", "password": "wrong password!"}
    )
    unknown = client.post(
        "/api/v1/auth/login", json={"email": "nobody@example.com", "password": "wrong password!"}
    )

    assert wrong.status_code == unknown.status_code == 401
    assert wrong.json()["code"] == unknown.json()["code"] == "invalid_credentials"


def test_the_11th_login_attempt_in_a_minute_is_rate_limited(client: TestClient) -> None:
    payload = {"email": "brute@example.com", "password": "wrong password!"}
    statuses = [client.post("/api/v1/auth/login", json=payload).status_code for _ in range(11)]

    assert statuses[:10] == [401] * 10
    limited = client.post("/api/v1/auth/login", json=payload)
    assert limited.status_code == 429
    assert limited.json()["code"] == "rate_limited"
    assert int(limited.headers["Retry-After"]) > 0


# --- access tokens --------------------------------------------------------------------------


def test_protected_routes_require_a_bearer_token(client: TestClient) -> None:
    missing = client.get("/api/v1/me")
    garbage = client.get("/api/v1/me", headers=bearer("not-a-jwt"))

    assert missing.status_code == garbage.status_code == 401
    assert missing.json()["code"] == "unauthenticated"
    assert missing.headers["WWW-Authenticate"] == "Bearer"


def test_expired_access_tokens_say_token_expired(client: TestClient) -> None:
    with time_machine.travel(NOW, tick=False):
        account = register(client)
    with time_machine.travel(NOW + timedelta(minutes=16), tick=False):
        response = client.get("/api/v1/me", headers=account.headers)

    assert response.status_code == 401
    assert response.json()["code"] == "token_expired"


# --- refresh rotation -----------------------------------------------------------------------


def test_refresh_rotates_the_refresh_token(client: TestClient) -> None:
    account = register(client)

    response = refresh(client, account.refresh_token)

    assert response.status_code == 200
    tokens = response.json()
    assert tokens["refresh_token"] != account.refresh_token
    assert client.get("/api/v1/me", headers=bearer(tokens["access_token"])).status_code == 200


def test_reusing_a_token_within_the_grace_window_reissues(client: TestClient) -> None:
    """The client lost the refresh response and retries with the old token."""
    with time_machine.travel(NOW, tick=False):
        account = register(client)
        lost = refresh(client, account.refresh_token).json()
    with time_machine.travel(NOW + timedelta(seconds=30), tick=False):
        retried = refresh(client, account.refresh_token)

    assert retried.status_code == 200
    # The successor from the lost response is dead; the new one works.
    assert refresh(client, lost["refresh_token"]).json()["code"] == "refresh_reuse_detected"


def test_reuse_after_the_grace_window_revokes_the_session(client: TestClient) -> None:
    with time_machine.travel(NOW, tick=False):
        account = register(client)
        current = refresh(client, account.refresh_token).json()
    with time_machine.travel(NOW + timedelta(seconds=61), tick=False):
        replay = refresh(client, account.refresh_token)
        after = refresh(client, current["refresh_token"])

    assert replay.status_code == 401
    assert replay.json()["code"] == "refresh_reuse_detected"
    assert after.status_code == 401  # the legitimate holder is signed out too


def test_reuse_after_the_successor_was_used_revokes_the_session(client: TestClient) -> None:
    account = register(client)
    second = refresh(client, account.refresh_token).json()
    refresh(client, second["refresh_token"])

    replay = refresh(client, account.refresh_token)

    assert replay.status_code == 401
    assert replay.json()["code"] == "refresh_reuse_detected"


def test_sessions_end_after_the_absolute_cap(client: TestClient) -> None:
    with time_machine.travel(NOW, tick=False):
        token = register(client).refresh_token
    # Refresh every 25 days to keep the sliding window alive...
    for days in range(25, 180, 25):
        with time_machine.travel(NOW + timedelta(days=days), tick=False):
            response = refresh(client, token)
            assert response.status_code == 200, days
            token = response.json()["refresh_token"]
    # ...but 180 days after login the session is over.
    with time_machine.travel(NOW + timedelta(days=180, minutes=1), tick=False):
        assert refresh(client, token).status_code == 401


def test_unknown_refresh_tokens_are_rejected(client: TestClient) -> None:
    response = refresh(client, "definitely-not-issued")

    assert response.status_code == 401
    assert response.json()["code"] == "unauthenticated"


# --- logout ---------------------------------------------------------------------------------


def test_logout_ends_the_session_and_is_idempotent(client: TestClient) -> None:
    account = register(client)

    first = client.post("/api/v1/auth/logout", json={"refresh_token": account.refresh_token})
    again = client.post("/api/v1/auth/logout", json={"refresh_token": account.refresh_token})
    unknown = client.post("/api/v1/auth/logout", json={"refresh_token": "whatever"})

    assert first.status_code == again.status_code == unknown.status_code == 204
    assert refresh(client, account.refresh_token).status_code == 401


def test_logout_all_ends_every_session_immediately(client: TestClient) -> None:
    account = register(client)
    other = login(client, account.email)

    response = client.post("/api/v1/auth/logout-all", headers=account.headers)

    assert response.status_code == 204
    assert client.get("/api/v1/me", headers=account.headers).status_code == 401
    assert (
        client.get("/api/v1/me", headers=bearer(other["tokens"]["access_token"])).status_code == 401
    )
    assert refresh(client, other["tokens"]["refresh_token"]).status_code == 401


# --- password change ------------------------------------------------------------------------


def test_changing_the_password_keeps_only_the_current_session(client: TestClient) -> None:
    account = register(client)
    other = login(client, account.email)

    response = client.post(
        "/api/v1/me/password",
        headers=account.headers,
        json={"current_password": DEFAULT_PASSWORD, "new_password": "a whole new password"},
    )

    assert response.status_code == 200
    tokens = response.json()
    assert client.get("/api/v1/me", headers=bearer(tokens["access_token"])).status_code == 200
    assert refresh(client, tokens["refresh_token"]).status_code == 200
    assert client.get("/api/v1/me", headers=account.headers).status_code == 401
    assert refresh(client, other["tokens"]["refresh_token"]).status_code == 401
    assert login(client, account.email, "a whole new password")["user"]["id"] == account.id


def test_changing_the_password_requires_the_current_one(client: TestClient) -> None:
    account = register(client)

    response = client.post(
        "/api/v1/me/password",
        headers=account.headers,
        json={"current_password": "not my password", "new_password": "a whole new password"},
    )

    assert response.status_code == 401
    assert response.json()["code"] == "invalid_credentials"
