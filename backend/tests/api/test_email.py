"""Email flows (contract section 18): verification, password reset, invites by email,
notification settings and unsubscribing."""

import uuid
from datetime import timedelta

import time_machine
from fastapi.testclient import TestClient

from friends_api.core.config import Settings
from friends_api.core.db import utcnow
from friends_api.core.mail import RecordingMailer
from friends_api.features.emails.tokens import NotificationKind, unsubscribe_token
from tests.factories import (
    add_member,
    create_group,
    create_invite,
    link_token,
    login,
    register,
    verify_email,
)


def me(client: TestClient, headers: dict[str, str]) -> dict[str, object]:
    body: dict[str, object] = client.get("/api/v1/me", headers=headers).json()
    return body


def test_signing_up_sends_a_verification_link(client: TestClient, mailer: RecordingMailer) -> None:
    account = register(client, display_name="Ana")

    assert me(client, account.headers)["email_verified"] is False
    (email,) = mailer.sent
    assert email.to == account.email
    assert email.subject == "Confirm your email for Friends"
    assert "Hi Ana," in email.text
    assert "http://localhost:5000/verify-email?token=" in email.text
    assert "/verify-email?token=" in email.html

    verify_email(client, account, mailer)

    assert me(client, account.headers)["email_verified"] is True
    again = client.post("/api/v1/auth/verify-email", json={"token": link_token(email.text)})
    assert again.status_code == 422
    assert again.json()["code"] == "invalid_token"
    assert again.json()["errors"][0]["field"] == "token"


def test_resending_replaces_the_link_and_stops_once_verified(
    client: TestClient, mailer: RecordingMailer
) -> None:
    account = register(client)
    first = mailer.sent[-1]

    assert client.post("/api/v1/me/email-verification", headers=account.headers).status_code == 202
    second = mailer.sent[-1]
    assert link_token(second.text) != link_token(first.text)
    old = client.post("/api/v1/auth/verify-email", json={"token": link_token(first.text)})
    assert old.json()["code"] == "invalid_token"

    verify_email(client, account, mailer)
    count = len(mailer.sent)
    assert client.post("/api/v1/me/email-verification", headers=account.headers).status_code == 202
    assert len(mailer.sent) == count  # already verified: nothing sent


def test_verification_links_expire_after_7_days(
    client: TestClient, mailer: RecordingMailer
) -> None:
    account = register(client)
    token = link_token(mailer.sent[-1].text)

    with time_machine.travel(utcnow() + timedelta(days=7, minutes=1)):
        response = client.post("/api/v1/auth/verify-email", json={"token": token})

    assert response.json()["code"] == "invalid_token"
    assert me(client, account.headers)["email_verified"] is False


def request_reset(client: TestClient, email: str) -> None:
    response = client.post("/api/v1/auth/password-reset/request", json={"email": email})
    assert response.status_code == 202, response.text


def test_a_reset_link_only_goes_to_a_verified_address(
    client: TestClient, mailer: RecordingMailer
) -> None:
    account = register(client)
    sent = len(mailer.sent)

    request_reset(client, account.email)
    request_reset(client, "nobody@example.com")
    assert len(mailer.sent) == sent  # same 202, nothing sent

    verify_email(client, account, mailer)
    request_reset(client, f"  {account.email.upper()} ")
    email = mailer.sent[-1]
    assert email.to == account.email
    assert email.subject == "Reset your Friends password"
    assert "http://localhost:5000/reset-password?token=" in email.text


def test_resetting_sets_the_password_and_signs_out_everywhere(
    client: TestClient, mailer: RecordingMailer
) -> None:
    account = register(client)
    verify_email(client, account, mailer)
    request_reset(client, account.email)
    token = link_token(mailer.sent[-1].text)

    response = client.post(
        "/api/v1/auth/password-reset", json={"token": token, "new_password": "a brand new secret"}
    )

    assert response.status_code == 204
    assert client.get("/api/v1/me", headers=account.headers).status_code == 401
    refreshed = client.post("/api/v1/auth/refresh", json={"refresh_token": account.refresh_token})
    assert refreshed.status_code == 401
    assert login(client, account.email, "a brand new secret")["user"]["id"] == account.id
    reused = client.post(
        "/api/v1/auth/password-reset", json={"token": token, "new_password": "yet another one"}
    )
    assert reused.json()["code"] == "invalid_token"


def test_reset_links_expire_after_an_hour_and_keep_the_password_rules(
    client: TestClient, mailer: RecordingMailer
) -> None:
    account = register(client)
    verify_email(client, account, mailer)
    request_reset(client, account.email)
    token = link_token(mailer.sent[-1].text)

    weak = client.post(
        "/api/v1/auth/password-reset", json={"token": token, "new_password": account.email}
    )
    assert weak.json()["code"] == "weak_password"
    with time_machine.travel(utcnow() + timedelta(minutes=61)):
        late = client.post(
            "/api/v1/auth/password-reset",
            json={"token": token, "new_password": "a brand new secret"},
        )
    assert late.json()["code"] == "invalid_token"


def test_a_new_reset_link_replaces_the_previous_one(
    client: TestClient, mailer: RecordingMailer
) -> None:
    account = register(client)
    verify_email(client, account, mailer)
    request_reset(client, account.email)
    first = link_token(mailer.sent[-1].text)
    request_reset(client, account.email)

    response = client.post(
        "/api/v1/auth/password-reset", json={"token": first, "new_password": "a brand new secret"}
    )

    assert response.json()["code"] == "invalid_token"


def test_deleting_the_account_voids_its_links(client: TestClient, mailer: RecordingMailer) -> None:
    account = register(client)
    token = link_token(mailer.sent[-1].text)
    deleted = client.post(
        "/api/v1/me/deletion", headers=account.headers, json={"password": account.password}
    )
    assert deleted.status_code == 204

    response = client.post("/api/v1/auth/verify-email", json={"token": token})

    assert response.json()["code"] == "invalid_token"


def test_inviting_by_email(client: TestClient, mailer: RecordingMailer) -> None:
    owner = register(client, display_name="Ana")
    group = create_group(client, owner, name="Hikers")
    invite = create_invite(client, owner, group["id"])
    path = f"/api/v1/groups/{group['id']}/invites/{invite['id']}/email"

    unverified = client.post(path, headers=owner.headers, json={"email": "bea@example.com"})
    assert unverified.status_code == 403
    assert unverified.json()["code"] == "email_not_verified"

    verify_email(client, owner, mailer)
    sent = client.post(path, headers=owner.headers, json={"email": "bea@example.com"})
    assert sent.status_code == 202
    email = mailer.sent[-1]
    assert email.to == "bea@example.com"
    assert email.subject == "Ana invited you to Hikers on Friends"
    assert invite["url"] in email.text

    bad = client.post(path, headers=owner.headers, json={"email": "not an email"})
    assert bad.status_code == 422
    client.delete(f"/api/v1/groups/{group['id']}/invites/{invite['id']}", headers=owner.headers)
    revoked = client.post(path, headers=owner.headers, json={"email": "bea@example.com"})
    assert revoked.status_code == 410


def test_notification_settings(client: TestClient) -> None:
    account = register(client)

    defaults = client.get("/api/v1/me/notifications", headers=account.headers).json()
    updated = client.put(
        "/api/v1/me/notifications",
        headers=account.headers,
        json={"polls": False, "wheel": True, "reminders": False},
    ).json()

    assert defaults == {"polls": True, "wheel": True, "reminders": True}
    assert updated == {"polls": False, "wheel": True, "reminders": False}
    assert client.get("/api/v1/me/notifications", headers=account.headers).json() == updated


def test_unsubscribing_from_a_notification_link(client: TestClient, settings: Settings) -> None:
    account = register(client)
    token = unsubscribe_token(settings, uuid.UUID(account.id), NotificationKind.WHEEL)

    # A mail app's RFC 8058 one-click POST: a form body.
    response = client.post(
        "/api/v1/notifications/unsubscribe",
        params={"token": token},
        data={"List-Unsubscribe": "One-Click"},
    )

    assert response.status_code == 200
    assert response.json() == {"kind": "wheel"}
    settings_now = client.get("/api/v1/me/notifications", headers=account.headers).json()
    assert settings_now == {"polls": True, "wheel": False, "reminders": True}
    forged = client.post("/api/v1/notifications/unsubscribe", params={"token": token + "x"})
    assert forged.json()["code"] == "invalid_token"


def test_another_members_invite_cannot_be_emailed(
    client: TestClient, mailer: RecordingMailer
) -> None:
    owner = register(client)
    group = create_group(client, owner)
    member = add_member(client, owner, group["id"])
    verify_email(client, member, mailer)
    invite = create_invite(client, owner, group["id"])

    response = client.post(
        f"/api/v1/groups/{group['id']}/invites/{invite['id']}/email",
        headers=member.headers,
        json={"email": "bea@example.com"},
    )

    assert response.status_code == 403
    assert response.json()["code"] == "forbidden"
