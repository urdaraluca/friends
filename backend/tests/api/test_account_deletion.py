from typing import Any

from fastapi.testclient import TestClient

from tests.factories import DEFAULT_PASSWORD, add_member, create_group, register


def delete_account(
    client: TestClient, headers: dict[str, str], password: str = DEFAULT_PASSWORD
) -> Any:
    return client.post("/api/v1/me/deletion", headers=headers, json={"password": password})


def test_wrong_password_keeps_the_account(client: TestClient) -> None:
    account = register(client)

    response = delete_account(client, account.headers, "not my password")

    assert response.status_code == 422
    assert response.json()["code"] == "wrong_password"
    assert response.json()["errors"][0]["field"] == "password"
    assert client.get("/api/v1/me", headers=account.headers).status_code == 200


def test_deletion_anonymizes_and_signs_out(client: TestClient) -> None:
    account = register(client, email="gone@example.com")

    response = delete_account(client, account.headers)

    assert response.status_code == 204
    assert client.get("/api/v1/me", headers=account.headers).status_code == 401
    login = client.post(
        "/api/v1/auth/login", json={"email": "gone@example.com", "password": DEFAULT_PASSWORD}
    )
    assert login.status_code == 401
    refresh = client.post("/api/v1/auth/refresh", json={"refresh_token": account.refresh_token})
    assert refresh.status_code == 401
    # The email address is free again.
    assert register(client, email="gone@example.com").email == "gone@example.com"


def test_ownership_goes_to_the_oldest_admin_then_member(client: TestClient) -> None:
    owner = register(client)
    group = create_group(client, owner)
    older_member = add_member(client, owner, group["id"])
    admin = add_member(client, owner, group["id"])
    client.put(
        f"/api/v1/groups/{group['id']}/members/{admin.id}/role",
        headers=owner.headers,
        json={"role": "admin"},
    )
    solo = create_group(client, owner, name="Just me")

    assert delete_account(client, owner.headers).status_code == 204

    members = client.get(f"/api/v1/groups/{group['id']}/members", headers=admin.headers).json()
    assert {m["user"]["id"]: m["role"] for m in members} == {
        admin.id: "owner",
        older_member.id: "member",
    }
    # The group only the deleted user was in is gone.
    assert client.get(f"/api/v1/groups/{solo['id']}", headers=admin.headers).status_code == 404


def test_without_admins_the_oldest_member_inherits(client: TestClient) -> None:
    owner = register(client)
    group = create_group(client, owner)
    first = add_member(client, owner, group["id"])
    add_member(client, owner, group["id"])

    delete_account(client, owner.headers)

    group_view = client.get(f"/api/v1/groups/{group['id']}", headers=first.headers).json()
    assert group_view["my_role"] == "owner"
    assert group_view["created_by"]["display_name"] == "Deleted user"
