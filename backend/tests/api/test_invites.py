from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta

import pytest
import time_machine
from fastapi.testclient import TestClient

from friends_api.core.config import RegistrationMode, Settings
from friends_api.features.invites.service import normalize_code
from friends_api.main import create_app
from tests.factories import (
    DEFAULT_PASSWORD,
    add_member,
    create_group,
    create_invite,
    join,
    register,
)

NOW = datetime(2026, 10, 1, 12, 0, tzinfo=UTC)


@pytest.mark.parametrize(
    ("raw", "normalized"),
    [
        ("abcd-efgh-jk", "ABCDEFGHJK"),
        (" abcd efgh ik ", "ABCDEFGH1K"),
        ("0O1IL23456", "0011123456"),
        ("ABCDEFGHJ", None),  # too short
        ("ABCDEFGHJU", None),  # U is not in the alphabet
    ],
)
def test_codes_are_normalized(raw: str, normalized: str | None) -> None:
    assert normalize_code(raw) == normalized


def test_create_and_accept_an_invite(client: TestClient, settings: Settings) -> None:
    owner = register(client)
    group = create_group(client, owner)
    invite = create_invite(client, owner, group["id"], max_uses=5)
    friend = register(client)

    assert invite["url"] == f"{settings.public_app_url}/join/{invite['code']}"
    assert invite["status"] == "valid"
    assert invite["can_delete"] is True

    joined = join(client, friend, invite["code"].lower())

    assert joined["id"] == group["id"]
    assert joined["my_role"] == "member"
    listed = client.get(f"/api/v1/groups/{group['id']}/invites", headers=owner.headers).json()
    assert listed[0]["use_count"] == 1


def test_accepting_twice_is_idempotent(client: TestClient) -> None:
    owner = register(client)
    group = create_group(client, owner)
    invite = create_invite(client, owner, group["id"], max_uses=1)
    friend = register(client)
    join(client, friend, invite["code"])

    again = client.post(f"/api/v1/invites/{invite['code']}/accept", headers=friend.headers)

    assert again.status_code == 200  # already a member: no use consumed, no 410


def test_preview_is_public_and_shows_the_status(client: TestClient) -> None:
    owner = register(client, display_name="Ana")
    group = create_group(client, owner, name="Hikers", emoji="🥾")
    invite = create_invite(client, owner, group["id"])

    preview = client.get(f"/api/v1/invites/{invite['code']}")

    assert preview.status_code == 200
    assert preview.json() == {
        "code": invite["code"],
        "status": "valid",
        "group": {"name": "Hikers", "emoji": "🥾", "color": None, "member_count": 1},
        "invited_by_name": "Ana",
        "expires_at": invite["expires_at"],
    }
    assert client.get("/api/v1/invites/NOPE").status_code == 404
    assert client.get("/api/v1/invites/0000000000").status_code == 404


def test_expired_revoked_and_exhausted_invites_are_gone(client: TestClient) -> None:
    with time_machine.travel(NOW, tick=False):
        owner = register(client)
        group = create_group(client, owner)
        expiring = create_invite(client, owner, group["id"], expires_in_hours=1)
        single = create_invite(client, owner, group["id"], max_uses=1)
        revoked = create_invite(client, owner, group["id"])
        client.delete(
            f"/api/v1/groups/{group['id']}/invites/{revoked['id']}", headers=owner.headers
        )
        join(client, register(client), single["code"])

    with time_machine.travel(NOW + timedelta(hours=2), tick=False):
        late = register(client)
        for invite, code in [
            (expiring, "invite_expired"),
            (revoked, "invite_revoked"),
            (single, "invite_exhausted"),
        ]:
            response = client.post(f"/api/v1/invites/{invite['code']}/accept", headers=late.headers)
            assert response.status_code == 410, code
            assert response.json()["code"] == code
            preview = client.get(f"/api/v1/invites/{invite['code']}").json()
            assert preview["status"] == code.removeprefix("invite_")


def test_concurrent_accepts_of_a_single_use_invite_join_once(settings: Settings) -> None:
    with TestClient(create_app(settings)) as client:
        owner = register(client)
        group = create_group(client, owner)
        invite = create_invite(client, owner, group["id"], max_uses=1)
        friends = [register(client) for _ in range(6)]

        def accept(headers: dict[str, str]) -> int:
            url = f"/api/v1/invites/{invite['code']}/accept"
            return client.post(url, headers=headers).status_code

        with ThreadPoolExecutor(max_workers=6) as pool:
            statuses = list(pool.map(accept, [f.headers for f in friends]))

        members = client.get(f"/api/v1/groups/{group['id']}/members", headers=owner.headers).json()

    assert sorted(statuses) == [200] + [410] * 5
    assert len(members) == 2


def test_members_see_only_their_own_invites_and_can_be_blocked(client: TestClient) -> None:
    owner = register(client)
    group = create_group(client, owner)
    member = add_member(client, owner, group["id"])
    mine = create_invite(client, member, group["id"])
    url = f"/api/v1/groups/{group['id']}/invites"

    seen_by_member = [i["id"] for i in client.get(url, headers=member.headers).json()]
    never = client.post(url, headers=member.headers, json={"never_expires": True})
    owners_invite = client.get(url, headers=owner.headers).json()[-1]
    revoke_owners = client.delete(f"{url}/{owners_invite['id']}", headers=member.headers)
    client.put(
        f"/api/v1/groups/{group['id']}",
        headers=owner.headers,
        json={"name": "G", "currency": "EUR", "timezone": "UTC", "members_can_invite": False},
    )
    blocked = client.post(url, headers=member.headers, json={})
    revoke_mine = client.delete(f"{url}/{mine['id']}", headers=member.headers)

    assert seen_by_member == [mine["id"]]
    assert never.status_code == 403
    assert revoke_owners.status_code == 403
    assert blocked.status_code == 403
    assert revoke_mine.status_code == 204


def test_never_expiring_invites_for_admins(client: TestClient) -> None:
    owner = register(client)
    group = create_group(client, owner)

    invite = create_invite(client, owner, group["id"], never_expires=True, expires_in_hours=1)

    assert invite["expires_at"] is None


# --- invite-only registration -------------------------------------------------------------


@pytest.fixture
def invite_only(settings: Settings) -> Settings:
    return settings.model_copy(update={"registration_mode": RegistrationMode.INVITE_ONLY})


def test_registration_needs_an_invite_when_invite_only(invite_only: Settings) -> None:
    with TestClient(create_app(invite_only)) as client:
        response = client.post(
            "/api/v1/auth/register",
            json={"email": "a@example.com", "password": DEFAULT_PASSWORD, "display_name": "A"},
        )

    assert response.status_code == 403
    assert response.json()["code"] == "registration_closed"


def test_registering_with_an_invite_joins_the_group(
    settings: Settings, invite_only: Settings
) -> None:
    with TestClient(create_app(settings)) as open_client:
        owner = register(open_client)
        group = create_group(open_client, owner, name="Climbers")
        invite = create_invite(open_client, owner, group["id"])

    with TestClient(create_app(invite_only)) as client:
        response = client.post(
            "/api/v1/auth/register",
            json={
                "email": "new@example.com",
                "password": DEFAULT_PASSWORD,
                "display_name": "New",
                "invite_code": invite["code"],
            },
        )
        bad_code = client.post(
            "/api/v1/auth/register",
            json={
                "email": "other@example.com",
                "password": DEFAULT_PASSWORD,
                "display_name": "Other",
                "invite_code": "ZZZZZZZZZZ",
            },
        )

    assert response.status_code == 201, response.text
    assert response.json()["joined_group"]["name"] == "Climbers"
    assert response.json()["joined_group"]["my_role"] == "member"
    assert bad_code.status_code == 404


def test_invite_problems_are_reported_before_email_problems(client: TestClient) -> None:
    owner = register(client, email="taken@example.com")
    group = create_group(client, owner)
    invite = create_invite(client, owner, group["id"])
    client.delete(f"/api/v1/groups/{group['id']}/invites/{invite['id']}", headers=owner.headers)

    response = client.post(
        "/api/v1/auth/register",
        json={
            "email": "taken@example.com",
            "password": DEFAULT_PASSWORD,
            "display_name": "X",
            "invite_code": invite["code"],
        },
    )

    assert response.status_code == 410
    assert response.json()["code"] == "invite_revoked"


def test_invites_expire_after_the_default_week(client: TestClient) -> None:
    with time_machine.travel(NOW, tick=False):
        owner = register(client)
        group = create_group(client, owner)
        invite = create_invite(client, owner, group["id"])

    assert invite["expires_at"] == (NOW + timedelta(days=7)).isoformat().replace("+00:00", "Z")
