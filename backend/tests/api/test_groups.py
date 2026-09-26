from typing import Any

from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from friends_api.features.group_log.models import GroupLog
from tests.factories import add_member, create_group, register

GROUP_UPDATE: dict[str, Any] = {
    "name": "Book club",
    "description": "Monthly-ish",
    "emoji": "📚",
    "color": "#aabbcc",
    "currency": "RON",
    "timezone": "Europe/Bucharest",
    "members_can_invite": False,
}


def test_create_group_makes_the_caller_owner(client: TestClient) -> None:
    owner = register(client, timezone="Europe/Bucharest")

    group = create_group(client, owner, name="  Hiking crew ", color="#2e7d32", emoji="🥾")

    assert group["name"] == "Hiking crew"
    assert group["color"] == "#2E7D32"
    assert group["my_role"] == "owner"
    assert group["member_count"] == 1
    assert group["currency"] == "EUR"
    assert group["timezone"] == "Europe/Bucharest"  # defaults to the creator's timezone
    assert group["created_by"]["id"] == owner.id
    assert group["description"] is None


def test_blank_optional_group_fields_mean_null(client: TestClient) -> None:
    """Contract 1.4: blank optional strings are null, even when they have a format."""
    owner = register(client, timezone="Europe/Bucharest")

    group = create_group(client, owner, color="", emoji=" ", timezone="", description="\n")

    assert group["color"] is group["emoji"] is group["description"] is None
    assert group["timezone"] == "Europe/Bucharest"  # null: the creator's timezone


def test_list_groups_returns_only_mine_sorted_by_name(client: TestClient) -> None:
    me, other = register(client), register(client)
    create_group(client, me, name="zebra")
    create_group(client, me, name="Alpha")
    create_group(client, other, name="Not mine")

    names = [g["name"] for g in client.get("/api/v1/groups", headers=me.headers).json()]

    assert names == ["Alpha", "zebra"]


def test_invalid_group_fields_are_rejected(client: TestClient) -> None:
    owner = register(client)

    for field, value in [
        ("color", "red"),
        ("currency", "eur"),
        ("timezone", "Nowhere/City"),
        ("name", "  "),
    ]:
        response = client.post(
            "/api/v1/groups", headers=owner.headers, json={"name": "G", field: value}
        )
        assert response.status_code == 422, (field, response.text)
        assert response.json()["errors"][0]["field"] == field


def test_admins_can_edit_the_group_members_cannot(client: TestClient) -> None:
    owner = register(client)
    group = create_group(client, owner)
    member = add_member(client, owner, group["id"])

    denied = client.put(f"/api/v1/groups/{group['id']}", headers=member.headers, json=GROUP_UPDATE)
    client.put(
        f"/api/v1/groups/{group['id']}/members/{member.id}/role",
        headers=owner.headers,
        json={"role": "admin"},
    )
    allowed = client.put(f"/api/v1/groups/{group['id']}", headers=member.headers, json=GROUP_UPDATE)

    assert denied.status_code == 403
    assert allowed.status_code == 200
    assert allowed.json()["name"] == "Book club"
    assert allowed.json()["my_role"] == "admin"


def test_members_are_listed_owner_admins_members_by_name(client: TestClient) -> None:
    owner = register(client, display_name="Zoe")
    group = create_group(client, owner)
    bob = add_member(client, owner, group["id"])
    ana = add_member(client, owner, group["id"])
    client.put(
        f"/api/v1/groups/{group['id']}/members/{bob.id}/role",
        headers=owner.headers,
        json={"role": "admin"},
    )

    members = client.get(f"/api/v1/groups/{group['id']}/members", headers=ana.headers).json()

    assert [(m["user"]["id"], m["role"]) for m in members] == [
        (owner.id, "owner"),
        (bob.id, "admin"),
        (ana.id, "member"),
    ]


def test_birthdays_are_shared_only_when_allowed(client: TestClient) -> None:
    owner = register(client)
    group = create_group(client, owner)
    friend = add_member(client, owner, group["id"])
    client.put(
        "/api/v1/me",
        headers=friend.headers,
        json={
            "display_name": "F",
            "timezone": "UTC",
            "birthday": {"month": 5, "day": 17, "year": 1990},
        },
    )

    def friend_row(viewer_headers: dict[str, str]) -> dict[str, Any]:
        rows = client.get(f"/api/v1/groups/{group['id']}/members", headers=viewer_headers).json()
        return next(r for r in rows if r["user"]["id"] == friend.id)

    assert friend_row(owner.headers)["birthday"] == {"month": 5, "day": 17}  # no year
    assert friend_row(owner.headers)["show_birthday"] is None

    hidden = client.put(
        f"/api/v1/groups/{group['id']}/members/me/settings",
        headers=friend.headers,
        json={"show_birthday": False},
    )
    assert hidden.json()["show_birthday"] is False
    assert hidden.json()["birthday"] == {"month": 5, "day": 17}  # always visible to yourself
    assert friend_row(owner.headers)["birthday"] is None


def test_transfer_ownership(client: TestClient) -> None:
    owner = register(client)
    group = create_group(client, owner)
    member = add_member(client, owner, group["id"])
    outsider = register(client)
    url = f"/api/v1/groups/{group['id']}/transfer-ownership"

    to_self = client.post(url, headers=owner.headers, json={"user_id": owner.id})
    to_outsider = client.post(url, headers=owner.headers, json={"user_id": outsider.id})
    response = client.post(url, headers=owner.headers, json={"user_id": member.id})

    assert to_self.status_code == 422
    assert to_outsider.status_code == 422
    assert to_outsider.json()["code"] == "invalid_reference"
    assert response.status_code == 200
    assert response.json()["my_role"] == "admin"
    roles = {
        m["user"]["id"]: m["role"]
        for m in client.get(f"/api/v1/groups/{group['id']}/members", headers=owner.headers).json()
    }
    assert roles == {owner.id: "admin", member.id: "owner"}


def test_the_owner_role_cannot_be_changed_directly(client: TestClient) -> None:
    owner = register(client)
    group = create_group(client, owner)

    response = client.put(
        f"/api/v1/groups/{group['id']}/members/{owner.id}/role",
        headers=owner.headers,
        json={"role": "member"},
    )

    assert response.status_code == 409
    assert response.json()["code"] == "owner_must_transfer"


def test_leaving_and_removing(client: TestClient) -> None:
    owner = register(client)
    group = create_group(client, owner)
    admin = add_member(client, owner, group["id"])
    member = add_member(client, owner, group["id"])
    other = add_member(client, owner, group["id"])
    members_url = f"/api/v1/groups/{group['id']}/members"
    client.put(f"{members_url}/{admin.id}/role", headers=owner.headers, json={"role": "admin"})

    owner_leaves = client.delete(f"{members_url}/{owner.id}", headers=owner.headers)
    member_removes_other = client.delete(f"{members_url}/{other.id}", headers=member.headers)
    admin_removes_owner = client.delete(f"{members_url}/{owner.id}", headers=admin.headers)
    admin_removes_member = client.delete(f"{members_url}/{other.id}", headers=admin.headers)
    member_leaves = client.delete(f"{members_url}/{member.id}", headers=member.headers)

    assert owner_leaves.status_code == 409
    assert owner_leaves.json()["code"] == "owner_must_transfer"
    assert member_removes_other.status_code == 403
    assert admin_removes_owner.status_code == 403
    assert admin_removes_member.status_code == 204
    assert member_leaves.status_code == 204
    assert client.get(f"/api/v1/groups/{group['id']}", headers=member.headers).status_code == 404
    remaining = {m["user"]["id"] for m in client.get(members_url, headers=owner.headers).json()}
    assert remaining == {owner.id, admin.id}


def test_the_last_member_leaving_deletes_the_group(client: TestClient) -> None:
    owner = register(client)
    group = create_group(client, owner)

    response = client.delete(
        f"/api/v1/groups/{group['id']}/members/{owner.id}", headers=owner.headers
    )

    assert response.status_code == 204
    assert client.get("/api/v1/groups", headers=owner.headers).json() == []


def test_only_the_owner_can_delete_the_group(client: TestClient) -> None:
    owner = register(client)
    group = create_group(client, owner)
    admin = add_member(client, owner, group["id"])
    client.put(
        f"/api/v1/groups/{group['id']}/members/{admin.id}/role",
        headers=owner.headers,
        json={"role": "admin"},
    )

    denied = client.delete(f"/api/v1/groups/{group['id']}", headers=admin.headers)
    deleted = client.delete(f"/api/v1/groups/{group['id']}", headers=owner.headers)

    assert denied.status_code == 403
    assert deleted.status_code == 204
    assert client.get(f"/api/v1/groups/{group['id']}", headers=owner.headers).status_code == 404


def test_group_changes_are_logged(client: TestClient, db_session: Session) -> None:
    owner = register(client)
    group = create_group(client, owner)
    member = add_member(client, owner, group["id"])
    client.put(f"/api/v1/groups/{group['id']}", headers=owner.headers, json=GROUP_UPDATE)
    client.delete(f"/api/v1/groups/{group['id']}/members/{member.id}", headers=member.headers)

    actions = db_session.scalars(select(GroupLog.action).order_by(GroupLog.id)).all()

    assert actions == [
        "group.created",
        "member.joined",
        *["category.created"] * 7,  # the default categories
        "invite.created",
        "member.joined",
        "group.updated",
        "member.left",
    ]
