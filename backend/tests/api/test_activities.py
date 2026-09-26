import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
import time_machine
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from friends_api.features.activities import service as activities_service
from friends_api.features.activities.models import Activity, ActivityInterest, ActivityStatus
from friends_api.features.group_log.models import GroupLog
from tests.factories import (
    DEFAULT_PASSWORD,
    Account,
    activity_update,
    add_member,
    create_activity,
    create_category,
    create_group,
    create_invite,
    join,
    list_categories,
    register,
)


def url(activity: dict[str, Any], suffix: str = "") -> str:
    return f"/api/v1/activities/{activity['id']}{suffix}"


def get(client: TestClient, account: Account, activity: dict[str, Any]) -> dict[str, Any]:
    response = client.get(url(activity), headers=account.headers)
    assert response.status_code == 200, response.text
    body: dict[str, Any] = response.json()
    return body


def put(client: TestClient, account: Account, activity: dict[str, Any], **changes: Any) -> Any:
    return client.put(
        url(activity), headers=account.headers, json=activity_update(activity, **changes)
    )


def make_admin(client: TestClient, owner: Account, group_id: str, account: Account) -> None:
    response = client.put(
        f"/api/v1/groups/{group_id}/members/{account.id}/role",
        headers=owner.headers,
        json={"role": "admin"},
    )
    assert response.status_code == 200


def interested_ids(activity: dict[str, Any]) -> set[str]:
    return {user["id"] for user in activity["interested_users"]}


class Crew:
    """A group (defaults seeded) with an owner, an admin and two plain members."""

    def __init__(self, client: TestClient) -> None:
        self.owner = register(client)
        self.group = create_group(client, self.owner, currency="RON")
        self.admin = add_member(client, self.owner, self.group["id"])
        make_admin(client, self.owner, self.group["id"], self.admin)
        self.alice = add_member(client, self.owner, self.group["id"])
        self.bob = add_member(client, self.owner, self.group["id"])
        self.categories = {
            c["name"]: c for c in list_categories(client, self.owner, self.group["id"])
        }

    @property
    def group_id(self) -> str:
        return str(self.group["id"])

    @property
    def movie_night(self) -> dict[str, Any]:
        return self.categories["Movie night"]


@pytest.fixture
def crew(client: TestClient) -> Crew:
    return Crew(client)


# --- create and read ----------------------------------------------------------------------


def test_create_activity_defaults(client: TestClient, crew: Crew) -> None:
    before = datetime.now(UTC)

    activity = create_activity(client, crew.alice, crew.group_id, title="  Picnic  ")

    assert activity["title"] == "Picnic"
    assert activity["status"] == "idea"
    assert activity["owner"]["id"] == crew.alice.id  # null means the creator
    assert activity["created_by"]["id"] == crew.alice.id
    assert activity["version"] == 1
    assert activity["interest_count"] == 1
    assert activity["i_am_interested"] is True
    assert interested_ids(activity) == {crew.alice.id}
    assert activity["completed_at"] is None
    assert datetime.fromisoformat(activity["status_changed_at"]) >= before
    assert (
        activity["poll_count"],
        activity["open_poll_count"],
        activity["my_unvoted_poll_count"],
    ) == (0, 0, 0)
    assert activity["next_occurrence"] is None
    assert activity["events"] == []
    assert activity["links"] == []
    assert activity["attributes"] == {}
    assert activity["card_attributes"] == []
    assert (activity["can_edit"], activity["can_delete"]) == (True, True)
    assert activity["estimated_cost"] is activity["currency"] is None
    assert activity["cost_per_person"] is True
    assert activity["category_id"] is None


def test_create_activity_with_every_field(client: TestClient, crew: Crew) -> None:
    activity = create_activity(
        client,
        crew.alice,
        crew.group_id,
        title="Movie marathon",
        description="All three",
        notes="Bring snacks",
        category_id=crew.movie_night["id"],
        owner_id=crew.bob.id,
        due_date="2026-12-01T00:00:00.000Z",
        estimated_cost=40,
        cost_per_person=False,
        location_name="Bob's place",
        address="Str. Exemplu 1, Bucharest",
        links=[
            {"url": "https://example.com/tickets", "label": " Tickets "},
            {"url": "http://x.io"},
        ],
        attributes={"genre": "Sci-fi", "imdb_rating": 8.5, "year": 1999},
        status="done",
    )

    assert activity["owner"]["id"] == crew.bob.id
    assert activity["due_date"] == "2026-12-01"
    assert (activity["estimated_cost"], activity["currency"]) == (40, "RON")  # group currency
    assert activity["links"] == [
        {"url": "https://example.com/tickets", "label": "Tickets"},
        {"url": "http://x.io", "label": None},
    ]
    assert activity["attributes"] == {"genre": "Sci-fi", "imdb_rating": 8.5, "year": 1999}
    assert activity["card_attributes"] == [
        {"key": "imdb_rating", "label": "IMDb rating", "type": "rating", "value": 8.5}
    ]
    assert activity["completed_at"] is not None  # created as done
    assert activity["completed_at"] == activity["status_changed_at"]


def test_currency_is_kept_with_a_cost_and_dropped_without_one(
    client: TestClient, crew: Crew
) -> None:
    priced = create_activity(client, crew.alice, crew.group_id, estimated_cost=0, currency="EUR")
    free = create_activity(client, crew.alice, crew.group_id, currency="EUR")

    assert (priced["estimated_cost"], priced["currency"]) == (0, "EUR")
    assert (free["estimated_cost"], free["currency"]) == (None, None)


def test_blank_optional_fields_mean_null(client: TestClient, crew: Crew) -> None:
    """Contract 1.4: an optional string that is empty after trimming is null, even for fields
    with a format (currency, dates, IDs)."""
    activity = create_activity(
        client,
        crew.alice,
        crew.group_id,
        estimated_cost=10,
        currency="",
        due_date=" ",
        category_id="",
        description="  ",
        location_name="",
    )

    assert (activity["estimated_cost"], activity["currency"]) == (10, "RON")  # group currency
    assert activity["due_date"] is None
    assert activity["category_id"] is None
    assert activity["description"] is activity["location_name"] is None

    updated = put(client, crew.alice, activity, currency=" ", due_date="", estimated_cost=20)
    assert updated.status_code == 200, updated.text
    assert (updated.json()["estimated_cost"], updated.json()["currency"]) == (20, "RON")
    assert updated.json()["due_date"] is None


@pytest.mark.parametrize(
    ("fields", "field", "error_type"),
    [
        ({"title": " "}, "title", "string_too_short"),
        ({"title": "t" * 121}, "title", "string_too_long"),
        ({"description": "d" * 5001}, "description", "string_too_long"),
        ({"estimated_cost": -1}, "estimated_cost", "greater_than_equal"),
        ({"estimated_cost": 10_000_001}, "estimated_cost", "less_than_equal"),
        ({"currency": "eur", "estimated_cost": 1}, "currency", "string_pattern_mismatch"),
        ({"due_date": "2026-10-01T21:00:00Z"}, "due_date", "value_error"),
        ({"due_date": "2026-10-01T00:00:00+02:00"}, "due_date", "value_error"),
        ({"links": [{"url": "not a url"}]}, "links.0.url", "value_error"),
        ({"links": [{"url": "ftp://example.com"}]}, "links.0.url", "value_error"),
        (
            {"links": [{"url": "https://x.io", "label": "l" * 61}]},
            "links.0.label",
            "string_too_long",
        ),
        ({"links": [{"url": "https://x.io"}] * 11}, "links", "too_long"),
        ({"status": "someday"}, "status", "enum"),
    ],
)
def test_invalid_activity_fields(
    client: TestClient, crew: Crew, fields: dict[str, Any], field: str, error_type: str
) -> None:
    response = client.post(
        f"/api/v1/groups/{crew.group_id}/activities",
        headers=crew.alice.headers,
        json={"title": "T", **fields},
    )

    assert response.status_code == 422, response.text
    assert response.json()["code"] == "validation_error"
    assert (field, error_type) in [(e["field"], e["type"]) for e in response.json()["errors"]]


def test_references_must_be_in_the_group(client: TestClient, crew: Crew) -> None:
    outsider = register(client)
    foreign_group = create_group(client, outsider)
    foreign_category = list_categories(client, outsider, foreign_group["id"])[0]

    for field, value in [("category_id", foreign_category["id"]), ("owner_id", outsider.id)]:
        response = client.post(
            f"/api/v1/groups/{crew.group_id}/activities",
            headers=crew.alice.headers,
            json={"title": "T", field: value},
        )
        assert response.status_code == 422
        assert response.json()["code"] == "invalid_reference"
        assert response.json()["errors"][0]["field"] == field


def test_activity_creation_is_logged(client: TestClient, crew: Crew, db_session: Session) -> None:
    activity = create_activity(
        client, crew.alice, crew.group_id, title="Logged", category_id=crew.movie_night["id"]
    )

    row = db_session.execute(
        select(GroupLog.actor_id, GroupLog.data).where(GroupLog.action == "activity.created")
    ).one()

    assert str(row.actor_id) == crew.alice.id
    assert row.data == {
        "title": "Logged",
        "category_id": crew.movie_night["id"],
        "status": "idea",
    }
    assert activity["interest_count"] == 1


# --- update (PUT) -------------------------------------------------------------------------


def test_put_replaces_the_content_and_bumps_the_version(
    client: TestClient, crew: Crew, db_session: Session
) -> None:
    activity = create_activity(
        client, crew.alice, crew.group_id, description="old", estimated_cost=10
    )

    response = put(
        client, crew.bob, activity, title="New title", description=None, estimated_cost=None
    )

    assert response.status_code == 200, response.text
    updated = response.json()
    assert updated["version"] == 2
    assert updated["title"] == "New title"
    assert updated["description"] is None
    assert (updated["estimated_cost"], updated["currency"]) == (None, None)
    again = put(client, crew.bob, updated)  # nothing changed: still a new version
    assert again.json()["version"] == 3
    fields = db_session.scalars(
        select(GroupLog.data).where(GroupLog.action == "activity.updated")
    ).all()
    assert fields == [{"fields": ["title", "description", "estimated_cost", "currency"]}]


def test_a_stale_version_is_a_conflict_and_changes_nothing(client: TestClient, crew: Crew) -> None:
    activity = create_activity(client, crew.alice, crew.group_id, title="Original")
    assert put(client, crew.bob, activity, title="First").status_code == 200

    stale = put(client, crew.alice, activity, title="Second")

    assert stale.status_code == 409
    assert stale.json()["code"] == "version_conflict"
    current = get(client, crew.alice, activity)
    assert (current["title"], current["version"]) == ("First", 2)


# Who changes the owner, from whom, to whom -> allowed?
OWNER_MATRIX = [
    ("alice", None, "alice", True),  # claim an unowned activity
    ("alice", None, "bob", False),  # ...but not assign it to someone else
    ("alice", "bob", "alice", False),  # no stealing
    ("alice", "bob", None, False),
    ("alice", "bob", "bob", True),  # no change
    ("bob", "bob", "alice", True),  # the owner hands it over...
    ("bob", "bob", None, True),  # ...or gives it up
    ("admin", "bob", "alice", True),  # admins+ may do anything
    ("admin", "bob", None, True),
    ("admin", None, "bob", True),
    ("owner", "alice", "bob", True),
    ("owner", None, "owner", True),
]


@pytest.mark.parametrize(("actor", "current", "new", "allowed"), OWNER_MATRIX)
def test_owner_change_matrix(
    client: TestClient,
    crew: Crew,
    actor: str,
    current: str | None,
    new: str | None,
    allowed: bool,
) -> None:
    people = {"alice": crew.alice, "bob": crew.bob, "admin": crew.admin, "owner": crew.owner}
    activity = create_activity(
        client, crew.owner, crew.group_id, owner_id=people[current].id if current else None
    )
    if current is None:  # "null means the creator" on create, so unown it first
        activity = put(client, crew.owner, activity, owner_id=None).json()
        assert activity["owner"] is None

    response = put(
        client, people[actor], activity, owner_id=people[new].id if new else None, title="Changed"
    )

    if allowed:
        assert response.status_code == 200, response.text
        owner = response.json()["owner"]
        assert (owner["id"] if owner else None) == (people[new].id if new else None)
    else:
        assert response.status_code == 403, response.text
        assert response.json()["code"] == "forbidden"
        assert get(client, crew.owner, activity)["title"] != "Changed"


def test_the_new_owner_must_be_a_member(client: TestClient, crew: Crew) -> None:
    activity = create_activity(client, crew.alice, crew.group_id)

    response = put(client, crew.alice, activity, owner_id=register(client).id)

    assert response.status_code == 422
    assert response.json()["code"] == "invalid_reference"


# --- attributes (contract sections 6.3 and 6.4) -------------------------------------------


def post_movie(client: TestClient, crew: Crew, attributes: dict[str, Any]) -> Any:
    return client.post(
        f"/api/v1/groups/{crew.group_id}/activities",
        headers=crew.alice.headers,
        json={"title": "Movie", "category_id": crew.movie_night["id"], "attributes": attributes},
    )


@pytest.mark.parametrize(
    ("attributes", "key", "error_type"),
    [
        ({"imdb_rating": 11}, "imdb_rating", "out_of_range"),
        ({"imdb_rating": 7.25}, "imdb_rating", "too_many_decimals"),
        ({"imdb_rating": True}, "imdb_rating", "wrong_type"),
        ({"year": True}, "year", "wrong_type"),
        ({"year": 1999.0}, "year", "wrong_type"),
        ({"runtime_min": 601}, "runtime_min", "out_of_range"),
        ({"runtime_min": 10**400}, "runtime_min", "out_of_range"),  # not a 500
        ({"genre": "Western"}, "genre", "not_an_option"),
        ({"imdb_url": "imdb.com/title/tt1"}, "imdb_url", "invalid_url"),
        ({"director": "Nolan"}, "director", "unknown_key"),
    ],
)
def test_invalid_attributes(
    client: TestClient, crew: Crew, attributes: dict[str, Any], key: str, error_type: str
) -> None:
    response = post_movie(client, crew, attributes)

    assert response.status_code == 422
    assert response.json()["code"] == "invalid_attributes"
    assert response.json()["errors"] == [
        {
            "field": f"attributes.{key}",
            "message": response.json()["errors"][0]["message"],
            "type": error_type,
        }
    ]


def test_all_bad_attributes_are_reported_together(client: TestClient, crew: Crew) -> None:
    response = post_movie(client, crew, {"imdb_rating": 11, "year": "1999", "extra": 1})

    assert [(e["field"], e["type"]) for e in response.json()["errors"]] == [
        ("attributes.imdb_rating", "out_of_range"),
        ("attributes.year", "wrong_type"),
        ("attributes.extra", "unknown_key"),
    ]


def test_uncategorized_activities_have_no_fields(client: TestClient, crew: Crew) -> None:
    response = client.post(
        f"/api/v1/groups/{crew.group_id}/activities",
        headers=crew.alice.headers,
        json={"title": "T", "attributes": {"genre": "Drama", "cleared": None}},
    )

    assert response.status_code == 422
    assert [e["field"] for e in response.json()["errors"]] == ["attributes.genre"]


def test_null_or_empty_clears_a_key(client: TestClient, crew: Crew, db_session: Session) -> None:
    movie = post_movie(client, crew, {"genre": "Drama", "year": 2001, "imdb_url": " "}).json()

    updated = put(
        client, crew.alice, movie, attributes={"genre": None, "year": 2001, "imdb_rating": ""}
    )

    assert updated.json()["attributes"] == {"year": 2001}
    stored = db_session.scalar(select(Activity.attributes))
    assert stored == {"year": 2001}  # no nulls in the stored JSON


def test_a_category_change_drops_the_old_categorys_keys(client: TestClient, crew: Crew) -> None:
    games = crew.categories["Games"]
    board_games = create_category(
        client,
        crew.owner,
        crew.group_id,
        name="Board games",
        parent_id=games["id"],
        field_defs=[{"key": "players", "label": "Players", "type": "number"}],
    )
    movie = post_movie(client, crew, {"genre": "Drama", "imdb_rating": 8}).json()

    moved = put(
        client,
        crew.alice,
        movie,
        category_id=board_games["id"],
        attributes={**movie["attributes"], "players": 4},
    )
    unknown = put(
        client,
        crew.alice,
        moved.json(),
        category_id=games["id"],
        attributes={"players": 4, "genre": "Drama"},
    )

    assert moved.status_code == 200, moved.text
    assert moved.json()["attributes"] == {"players": 4}
    # Moving back up drops "players" silently, but "genre" never belonged to Board games.
    assert unknown.status_code == 422
    assert [e["field"] for e in unknown.json()["errors"]] == ["attributes.genre"]


def test_stale_values_are_hidden_on_read(client: TestClient, crew: Crew) -> None:
    category = create_category(
        client,
        crew.owner,
        crew.group_id,
        field_defs=[
            {"key": "level", "label": "Level", "type": "select", "options": ["Low", "High"]},
            {"key": "score", "label": "Score", "type": "rating", "show_on_card": True},
            {"key": "note", "label": "Note", "type": "text"},
        ],
    )
    activity = create_activity(
        client,
        crew.alice,
        crew.group_id,
        category_id=category["id"],
        attributes={"level": "High", "score": 9, "note": "keep"},
    )
    body = {
        "name": category["name"],
        "parent_id": None,
        "color": category["color"],
        "field_defs": [
            {"key": "level", "label": "Level", "type": "select", "options": ["Low", "Medium"]},
            {"key": "score", "label": "Score", "type": "rating", "max": 5, "show_on_card": True},
            {"key": "note", "label": "Note", "type": "text"},
        ],
    }
    client.put(f"/api/v1/categories/{category['id']}", headers=crew.owner.headers, json=body)

    after = get(client, crew.alice, activity)

    assert after["attributes"] == {"note": "keep"}
    assert after["card_attributes"] == []
    assert after["version"] == activity["version"]  # GET never writes


def test_card_attributes_hold_only_show_on_card_fields_in_definition_order(
    client: TestClient, crew: Crew
) -> None:
    classics = create_category(
        client,
        crew.owner,
        crew.group_id,
        name="Classics",
        parent_id=crew.movie_night["id"],
        field_defs=[{"key": "director", "label": "Director", "type": "text", "show_on_card": True}],
    )
    activity = create_activity(
        client,
        crew.alice,
        crew.group_id,
        category_id=classics["id"],
        attributes={"director": "Billy Wilder", "genre": "Comedy", "imdb_rating": 8.2},
    )

    listed = client.get(
        f"/api/v1/groups/{crew.group_id}/activities", headers=crew.bob.headers
    ).json()["items"]

    expected = [
        {"key": "imdb_rating", "label": "IMDb rating", "type": "rating", "value": 8.2},
        {"key": "director", "label": "Director", "type": "text", "value": "Billy Wilder"},
    ]
    assert activity["card_attributes"] == expected
    assert listed[0]["card_attributes"] == expected


# --- delete -------------------------------------------------------------------------------


def test_who_may_delete_an_activity(client: TestClient, crew: Crew) -> None:
    created_by_alice = create_activity(client, crew.alice, crew.group_id, owner_id=crew.owner.id)
    owned_by_alice = create_activity(client, crew.owner, crew.group_id, owner_id=crew.alice.id)
    neither = create_activity(client, crew.owner, crew.group_id)

    plain_member = client.delete(url(neither), headers=crew.alice.headers)
    listed = {
        a["id"]: a["can_delete"]
        for a in client.get(
            f"/api/v1/groups/{crew.group_id}/activities", headers=crew.alice.headers
        ).json()["items"]
    }

    assert plain_member.status_code == 403
    assert plain_member.json()["code"] == "forbidden"
    assert listed == {
        created_by_alice["id"]: True,
        owned_by_alice["id"]: True,
        neither["id"]: False,
    }
    assert client.delete(url(created_by_alice), headers=crew.alice.headers).status_code == 204
    assert client.delete(url(owned_by_alice), headers=crew.alice.headers).status_code == 204
    assert client.delete(url(neither), headers=crew.admin.headers).status_code == 204
    assert client.get(url(neither), headers=crew.owner.headers).status_code == 404


def test_deleting_runs_the_delete_hooks_and_cascades_interests(
    client: TestClient, crew: Crew, monkeypatch: pytest.MonkeyPatch, db_session: Session
) -> None:
    seen: list[str] = []
    monkeypatch.setattr(
        activities_service,
        "ACTIVITY_DELETE_HOOKS",
        [
            *activities_service.ACTIVITY_DELETE_HOOKS,
            lambda db, activity: seen.append(activity.title),
        ],
    )
    activity = create_activity(client, crew.alice, crew.group_id, title="Doomed")
    client.put(url(activity, "/interest"), headers=crew.bob.headers)

    assert client.delete(url(activity), headers=crew.alice.headers).status_code == 204

    assert seen == ["Doomed"]
    assert db_session.scalar(select(Activity.id)) is None
    assert db_session.scalar(select(ActivityInterest.user_id)) is None
    deleted = db_session.scalars(
        select(GroupLog.data).where(GroupLog.action == "activity.deleted")
    ).all()
    assert deleted == [{"title": "Doomed"}]


# --- status -------------------------------------------------------------------------------


def test_status_changes(client: TestClient, crew: Crew, db_session: Session) -> None:
    activity = create_activity(client, crew.alice, crew.group_id)

    def set_status(status: str, at: datetime) -> dict[str, Any]:
        with time_machine.travel(at, tick=False):
            response = client.post(
                url(activity, "/status"), headers=crew.bob.headers, json={"status": status}
            )
        assert response.status_code == 200, response.text
        body: dict[str, Any] = response.json()
        return body

    # Minutes apart, so the access token (15 minutes) stays valid.
    start = datetime.now(UTC).replace(microsecond=0)
    t1, t2, t3, t4 = (start + timedelta(minutes=m) for m in (1, 2, 3, 4))
    done = set_status("done", t1)
    done_again = set_status("done", t2)
    dropped = set_status("dropped", t3)
    back_to_idea = set_status("idea", t4)

    assert done["status"] == "done"
    assert datetime.fromisoformat(done["completed_at"]) == t1
    assert datetime.fromisoformat(done["status_changed_at"]) == t1
    assert done_again == done  # the same status is a no-op
    assert dropped["completed_at"] is None  # left done
    assert datetime.fromisoformat(dropped["status_changed_at"]) == t3
    assert back_to_idea["status"] == "idea"
    assert back_to_idea["version"] == 1  # status changes don't touch the version
    rows = db_session.scalars(
        select(GroupLog.data)
        .where(GroupLog.action == "activity.status_changed")
        .order_by(GroupLog.id)
    ).all()
    assert rows == [
        {"from": "idea", "to": "done", "via": "status"},
        {"from": "done", "to": "dropped", "via": "status"},
        {"from": "dropped", "to": "idea", "via": "status"},
    ]


def test_other_features_change_the_status_through_the_service(
    client: TestClient, crew: Crew, db_session: Session
) -> None:
    """The wheel (accept) and events (scheduling) reuse ``change_status`` with their ``via``."""
    created = create_activity(client, crew.alice, crew.group_id, status="done")
    activity = db_session.get_one(Activity, uuid.UUID(created["id"]))

    at = datetime.now(UTC).replace(microsecond=0) + timedelta(minutes=1)
    with time_machine.travel(at, tick=False):
        changed = activities_service.change_status(
            db_session, activity, ActivityStatus.PLANNING, actor_id=None, via="wheel"
        )
        unchanged = activities_service.change_status(
            db_session, activity, ActivityStatus.PLANNING, actor_id=None, via="event"
        )
    db_session.commit()

    assert (changed, unchanged) == (True, False)
    after = get(client, crew.alice, created)
    assert (after["status"], after["completed_at"], after["version"]) == ("planning", None, 1)
    assert datetime.fromisoformat(after["status_changed_at"]) == at
    logged = db_session.scalars(
        select(GroupLog.data).where(GroupLog.action == "activity.status_changed")
    ).all()
    assert logged == [{"from": "done", "to": "planning", "via": "wheel"}]


# --- interests ----------------------------------------------------------------------------


def test_interests_are_idempotent(client: TestClient, crew: Crew, db_session: Session) -> None:
    activity = create_activity(client, crew.alice, crew.group_id)

    first = client.put(url(activity, "/interest"), headers=crew.bob.headers)
    second = client.put(url(activity, "/interest"), headers=crew.bob.headers)
    removed = client.delete(url(activity, "/interest"), headers=crew.alice.headers)
    removed_again = client.delete(url(activity, "/interest"), headers=crew.alice.headers)

    assert first.status_code == second.status_code == 200
    assert first.json() == second.json()
    assert second.json()["activity_id"] == activity["id"]
    assert second.json()["interested"] is True
    assert second.json()["interest_count"] == 2
    assert [u["id"] for u in second.json()["interested_users"]] == [crew.alice.id, crew.bob.id]
    assert removed.json() == removed_again.json()
    assert removed.json()["interested"] is False
    assert removed.json()["interest_count"] == 1
    actions = db_session.scalars(
        select(GroupLog.action)
        .where(GroupLog.action.like("activity.interest%"))
        .order_by(GroupLog.id)
    ).all()
    assert actions == ["activity.interest_added", "activity.interest_removed"]
    view = get(client, crew.bob, activity)
    assert (view["i_am_interested"], view["interest_count"]) == (True, 1)


# --- membership end (contract section 7.5) ------------------------------------------------


class Leaver:
    """bob owns one activity and is interested in another, both in the crew group and in a
    second group ("Elsewhere") that he also belongs to."""

    def __init__(self, client: TestClient, crew: Crew) -> None:
        self.elsewhere = create_group(client, crew.alice, name="Elsewhere")
        join(client, crew.bob, create_invite(client, crew.alice, self.elsewhere["id"])["code"])
        self.owned, self.liked = self._own_and_like(client, crew, crew.group_id)
        self.owned_elsewhere, self.liked_elsewhere = self._own_and_like(
            client, crew, self.elsewhere["id"]
        )

    @staticmethod
    def _own_and_like(
        client: TestClient, crew: Crew, group_id: str
    ) -> tuple[dict[str, Any], dict[str, Any]]:
        owned = create_activity(client, crew.bob, group_id, title="Bob's")
        liked = create_activity(client, crew.alice, group_id, title="Alice's")
        response = client.put(url(liked, "/interest"), headers=crew.bob.headers)
        assert response.status_code == 200
        return owned, liked


def _assert_bob_is_gone(
    client: TestClient, crew: Crew, owned: dict[str, Any], liked: dict[str, Any]
) -> None:
    after_owned = get(client, crew.alice, owned)
    after_liked = get(client, crew.alice, liked)
    assert after_owned["owner"] is None
    assert after_owned["version"] == owned["version"] + 1
    assert after_owned["created_by"]["id"] == crew.bob.id  # authored content stays
    assert crew.bob.id not in interested_ids(after_owned)
    assert interested_ids(after_liked) == {crew.alice.id}
    assert after_liked["version"] == liked["version"]


def _assert_bob_is_still_there(
    client: TestClient, crew: Crew, owned: dict[str, Any], liked: dict[str, Any]
) -> None:
    after_owned = get(client, crew.alice, owned)
    after_liked = get(client, crew.alice, liked)
    assert after_owned["owner"]["id"] == crew.bob.id
    assert after_owned["version"] == owned["version"]
    assert interested_ids(after_owned) == {crew.bob.id}
    assert interested_ids(after_liked) == {crew.alice.id, crew.bob.id}
    assert after_liked["version"] == liked["version"]


def test_leaving_the_group_clears_interests_and_ownership_there_only(
    client: TestClient, crew: Crew
) -> None:
    leaver = Leaver(client, crew)

    response = client.delete(
        f"/api/v1/groups/{crew.group_id}/members/{crew.bob.id}", headers=crew.bob.headers
    )

    assert response.status_code == 204
    _assert_bob_is_gone(client, crew, leaver.owned, leaver.liked)
    _assert_bob_is_still_there(client, crew, leaver.owned_elsewhere, leaver.liked_elsewhere)


def test_being_removed_clears_interests_and_ownership_there_only(
    client: TestClient, crew: Crew
) -> None:
    leaver = Leaver(client, crew)

    response = client.delete(
        f"/api/v1/groups/{crew.group_id}/members/{crew.bob.id}", headers=crew.admin.headers
    )

    assert response.status_code == 204
    _assert_bob_is_gone(client, crew, leaver.owned, leaver.liked)
    _assert_bob_is_still_there(client, crew, leaver.owned_elsewhere, leaver.liked_elsewhere)


def test_account_deletion_clears_interests_and_ownership_in_every_group(
    client: TestClient, crew: Crew
) -> None:
    leaver = Leaver(client, crew)

    response = client.post(
        "/api/v1/me/deletion", headers=crew.bob.headers, json={"password": DEFAULT_PASSWORD}
    )

    assert response.status_code == 204
    _assert_bob_is_gone(client, crew, leaver.owned, leaver.liked)
    _assert_bob_is_gone(client, crew, leaver.owned_elsewhere, leaver.liked_elsewhere)
    assert get(client, crew.alice, leaver.owned)["created_by"]["display_name"] == "Deleted user"
