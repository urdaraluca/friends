"""The group feed (contract section 15)."""

from typing import Any

from fastapi.testclient import TestClient

from tests.factories import (
    Account,
    add_member,
    create_activity,
    create_event,
    create_group,
    create_invite,
    create_poll,
    register,
)


def feed(client: TestClient, account: Account, group_id: str, **params: Any) -> dict[str, Any]:
    response = client.get(f"/api/v1/groups/{group_id}/feed", headers=account.headers, params=params)
    assert response.status_code == 200, response.text
    body: dict[str, Any] = response.json()
    return body


def test_the_feed_lists_what_happened_newest_first(client: TestClient) -> None:
    ana = register(client, display_name="Ana")
    group = create_group(client, ana)
    gid = group["id"]
    bea = add_member(client, ana, gid)
    idea = create_activity(client, bea, gid, title="Picnic")
    client.put(f"/api/v1/activities/{idea['id']}/interest", headers=ana.headers)
    client.post(
        f"/api/v1/activities/{idea['id']}/status", headers=ana.headers, json={"status": "done"}
    )
    event = create_event(client, ana, gid, title="Game night")
    poll = create_poll(client, bea, idea["id"], question="Where?")

    items = feed(client, bea, gid)["items"]

    assert [item["action"] for item in items] == [
        "poll.created",
        "event.created",
        "activity.status_changed",
        "activity.interest_added",
        "activity.created",
        "member.joined",
        "member.joined",
        "group.created",
    ]
    by_action = {item["action"]: item for item in items}
    assert by_action["poll.created"]["subject_title"] == "Where?"
    assert by_action["poll.created"]["subject_id"] == poll["id"]
    assert by_action["poll.created"]["data"] == {"activity_id": idea["id"]}
    assert by_action["event.created"]["subject_title"] == "Game night"
    assert by_action["event.created"]["subject_id"] == event["id"]
    assert by_action["activity.status_changed"]["data"] == {
        "from": "idea",
        "to": "done",
        "via": "status",
    }
    assert by_action["activity.status_changed"]["actor"]["display_name"] == "Ana"
    assert by_action["activity.created"]["subject_title"] == "Picnic"
    assert by_action["activity.created"]["subject_exists"] is True
    # Members are named by their subject.
    joined = [item for item in items if item["action"] == "member.joined"]
    assert {item["subject_title"] for item in joined} == {"Ana", bea.body["user"]["display_name"]}


def test_invites_and_personal_settings_stay_out(client: TestClient) -> None:
    ana = register(client)
    gid = create_group(client, ana)["id"]
    create_invite(client, ana, gid)
    client.patch(
        f"/api/v1/groups/{gid}/members/me/settings",
        headers=ana.headers,
        json={"show_birthday": False},
    )
    idea = create_activity(client, ana, gid)
    client.delete(f"/api/v1/activities/{idea['id']}/interest", headers=ana.headers)

    actions = [item["action"] for item in feed(client, ana, gid)["items"]]

    assert actions == ["activity.created", "member.joined", "group.created"]


def test_a_deleted_subject_keeps_its_logged_title(client: TestClient) -> None:
    ana = register(client)
    gid = create_group(client, ana)["id"]
    idea = create_activity(client, ana, gid, title="Karaoke")
    client.delete(f"/api/v1/activities/{idea['id']}", headers=ana.headers)

    items = feed(client, ana, gid)["items"]

    deleted, created = items[0], items[1]
    assert deleted["action"] == "activity.deleted"
    assert deleted["subject_title"] == "Karaoke"
    assert deleted["subject_exists"] is False
    assert deleted["data"] == {}  # the title is in subject_title
    assert created["subject_title"] == "Karaoke"
    assert created["subject_exists"] is False


def test_the_feed_is_paged(client: TestClient) -> None:
    ana = register(client)
    gid = create_group(client, ana)["id"]
    for n in range(4):
        create_activity(client, ana, gid, title=f"Idea {n}")

    first = feed(client, ana, gid, limit=3)
    second = feed(client, ana, gid, limit=3, cursor=first["next_cursor"])

    assert [i["subject_title"] for i in first["items"]] == ["Idea 3", "Idea 2", "Idea 1"]
    name = ana.body["user"]["display_name"]
    assert [i["subject_title"] for i in second["items"]] == ["Idea 0", name, "Friends"]
    assert second["items"][2]["action"] == "group.created"
    assert second["items"][2]["subject_exists"] is True
    assert second["next_cursor"] is None


def test_the_wheel_names_its_result(client: TestClient) -> None:
    ana = register(client)
    gid = create_group(client, ana)["id"]
    ideas = [create_activity(client, ana, gid, title=title) for title in ("Bowling", "Sushi")]
    response = client.post(
        f"/api/v1/groups/{gid}/wheel/spins",
        headers=ana.headers,
        json={"filters": {}, "activity_ids": [idea["id"] for idea in ideas]},
    )
    assert response.status_code == 201, response.text
    spin = response.json()
    client.post(f"/api/v1/wheel/spins/{spin['id']}/accept", headers=ana.headers)

    items = feed(client, ana, gid)["items"]

    wheel = [item for item in items if item["action"].startswith("wheel.")]
    assert [item["action"] for item in wheel] == ["wheel.accepted", "wheel.spun"]
    title = spin["result"]["title"]
    assert all(item["subject_title"] == title for item in wheel)
    assert wheel[1]["data"] == {
        "result_activity_id": spin["result_activity_id"],
        "candidate_count": 2,
    }
    assert wheel[0]["data"] == {"activity_id": spin["result_activity_id"]}
