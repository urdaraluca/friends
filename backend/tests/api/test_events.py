"""Events API (contract sections 5.6, 5.8, 7.2 and 8.8)."""

import uuid
from collections.abc import Iterator
from contextlib import contextmanager
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
import time_machine
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from friends_api.features.activities.models import Activity
from friends_api.features.events.models import Event, EventException
from friends_api.features.group_log.models import GroupLog
from tests.factories import (
    Account,
    add_member,
    bearer,
    create_activity,
    create_category,
    create_group,
    list_categories,
    login,
    register,
)

WEEKLY_THURSDAY = {
    "kind": "recurring",
    "all_day": False,
    "starts_at": "2026-10-01T16:00:00Z",  # 19:00 in Bucharest
    "ends_at": "2026-10-01T19:00:00Z",
    "rrule": "FREQ=WEEKLY;BYDAY=TH",
}
EVENT_WRITE_FIELDS = (
    "kind",
    "title",
    "description",
    "all_day",
    "starts_at",
    "ends_at",
    "start_date",
    "end_date",
    "timezone",
    "rrule",
    "category_id",
    "activity_id",
    "location_name",
    "address",
)


def url(event: dict[str, Any], suffix: str = "") -> str:
    return f"/api/v1/events/{event['id']}{suffix}"


def event_update(event: dict[str, Any], **changes: Any) -> dict[str, Any]:
    """A complete PUT body built from an ``Event`` response, with ``changes`` applied."""
    return {**{f: event[f] for f in EVENT_WRITE_FIELDS}, "version": event["version"], **changes}


def make_admin(client: TestClient, owner: Account, group_id: str, account: Account) -> None:
    response = client.put(
        f"/api/v1/groups/{group_id}/members/{account.id}/role",
        headers=owner.headers,
        json={"role": "admin"},
    )
    assert response.status_code == 200


class Crew:
    """A group in Europe/Bucharest with an owner, an admin and two plain members."""

    def __init__(self, client: TestClient) -> None:
        self.client = client
        self.owner = register(client)
        self.group = create_group(client, self.owner, timezone="Europe/Bucharest")
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

    def post(self, account: Account, **fields: Any) -> Any:
        payload = {"title": "Game night", **fields}
        return self.client.post(
            f"/api/v1/groups/{self.group_id}/events", headers=account.headers, json=payload
        )

    def get(self, account: Account, event: dict[str, Any]) -> dict[str, Any]:
        response = self.client.get(url(event), headers=account.headers)
        assert response.status_code == 200, response.text
        body: dict[str, Any] = response.json()
        return body

    def put(self, account: Account, event: dict[str, Any], **changes: Any) -> Any:
        return self.client.put(
            url(event), headers=account.headers, json=event_update(event, **changes)
        )

    def activity(self, client: TestClient, **fields: Any) -> dict[str, Any]:
        return create_activity(client, self.owner, self.group_id, **fields)


@pytest.fixture
def crew(client: TestClient) -> Crew:
    return Crew(client)


@contextmanager
def signed_in_at(client: TestClient, account: Account, when: datetime) -> Iterator[dict[str, str]]:
    """Travels to ``when`` and signs in again there (access tokens live 15 minutes)."""
    with time_machine.travel(when, tick=False):
        yield bearer(login(client, account.email, account.password)["tokens"]["access_token"])


def errors(response: Any) -> list[tuple[str, str]]:
    return [(e["field"], e["type"]) for e in response.json()["errors"]]


# --- creating -----------------------------------------------------------------------------


def test_create_a_weekly_event(client: TestClient, crew: Crew, db_session: Session) -> None:
    response = crew.post(
        crew.alice,
        **{**WEEKLY_THURSDAY, "rrule": "rrule:byday=th;freq=weekly"},
        description="Bring snacks",
        location_name="Ana's place",
        address="Str. Lalelelor 1",
    )

    assert response.status_code == 201, response.text
    event = response.json()
    assert event == {
        "id": event["id"],
        "group_id": crew.group_id,
        "kind": "recurring",
        "title": "Game night",
        "description": "Bring snacks",
        "all_day": False,
        "starts_at": "2026-10-01T16:00:00Z",
        "ends_at": "2026-10-01T19:00:00Z",
        "start_date": None,
        "end_date": None,
        "timezone": "Europe/Bucharest",  # the group's
        "rrule": "FREQ=WEEKLY;BYDAY=TH",
        "category_id": None,
        "color": None,
        "activity_id": None,
        "location_name": "Ana's place",
        "address": "Str. Lalelelor 1",
        "cancelled_occurrence_keys": [],
        "version": 1,
        "created_by": {
            "id": crew.alice.id,
            "display_name": crew.alice.body["user"]["display_name"],
            "avatar_url": None,
        },
        "can_edit": True,
        "can_delete": True,
        "created_at": event["created_at"],
        "updated_at": event["updated_at"],
    }
    row = db_session.get(Event, uuid.UUID(event["id"]))
    assert row is not None
    assert row.window_start == datetime(2026, 10, 1, 16, tzinfo=UTC)
    assert row.window_end is None
    log = db_session.scalars(select(GroupLog).where(GroupLog.action == "event.created")).one()
    assert log.subject_type == "event"
    assert str(log.subject_id) == event["id"]
    assert log.data == {"title": "Game night", "kind": "recurring"}


def test_create_timed_one_time_and_all_day_events(client: TestClient, crew: Crew) -> None:
    dinner = crew.post(
        crew.bob,
        kind="one_time",
        all_day=False,
        starts_at="2026-10-02T20:00:00+03:00",  # any offset, stored as UTC
        ends_at="2026-10-02T23:00:00+03:00",
        timezone="America/New_York",
    )
    trip = crew.post(
        crew.bob, kind="one_time", all_day=True, start_date="2026-10-09", end_date="2026-10-11"
    )
    same_day = crew.post(
        crew.bob, kind="one_time", all_day=True, start_date="2026-10-09T00:00:00.000Z"
    )

    assert dinner.status_code == 201, dinner.text
    assert (dinner.json()["starts_at"], dinner.json()["ends_at"]) == (
        "2026-10-02T17:00:00Z",
        "2026-10-02T20:00:00Z",
    )
    assert dinner.json()["timezone"] == "America/New_York"
    assert dinner.json()["rrule"] is None
    assert trip.status_code == 201, trip.text
    assert (trip.json()["start_date"], trip.json()["end_date"]) == ("2026-10-09", "2026-10-11")
    assert same_day.json()["end_date"] == "2026-10-09"  # null end_date means the same day


def test_window_end_for_count_and_open_ended_rules(
    client: TestClient, crew: Crew, db_session: Session
) -> None:
    three = crew.post(crew.alice, **{**WEEKLY_THURSDAY, "rrule": "FREQ=WEEKLY;BYDAY=TH;COUNT=3"})
    open_ended = crew.post(crew.alice, **WEEKLY_THURSDAY)
    until = crew.post(
        crew.alice, **{**WEEKLY_THURSDAY, "rrule": "FREQ=DAILY;UNTIL=20261010T000000Z"}
    )

    def window(response: Any) -> tuple[datetime, datetime | None]:
        row = db_session.scalars(
            select(Event).where(Event.id == uuid.UUID(response.json()["id"]))
        ).one()
        return row.window_start, row.window_end

    start = datetime(2026, 10, 1, 16, tzinfo=UTC)
    assert window(three) == (start, datetime(2026, 10, 15, 19, tzinfo=UTC))
    assert window(open_ended) == (start, None)
    assert window(until) == (start, datetime(2026, 10, 10, 3, tzinfo=UTC))


def test_birthday_events(client: TestClient, crew: Crew) -> None:
    feb29 = crew.post(
        crew.alice, kind="birthday", title="Grandma", all_day=True, start_date="2028-02-29"
    )
    explicit = crew.post(
        crew.alice,
        kind="birthday",
        title="Mihai",
        all_day=True,
        start_date="1990-06-12",
        end_date="1990-06-12",
        rrule=" rrule:freq=yearly ",
    )

    assert feb29.status_code == 201, feb29.text  # not run through 5.2: no yearly_feb29
    assert (feb29.json()["rrule"], feb29.json()["end_date"]) == ("FREQ=YEARLY", "2028-02-29")
    assert explicit.status_code == 201, explicit.text
    assert explicit.json()["rrule"] == "FREQ=YEARLY"


@pytest.mark.parametrize(
    ("fields", "expected"),
    [
        ({**WEEKLY_THURSDAY, "kind": "one_time"}, [("rrule", "value_error")]),
        ({**WEEKLY_THURSDAY, "rrule": None}, [("rrule", "missing")]),
        ({**WEEKLY_THURSDAY, "rrule": "  "}, [("rrule", "missing")]),
        (
            {**WEEKLY_THURSDAY, "start_date": "2026-10-01", "end_date": "2026-10-01"},
            [("start_date", "value_error"), ("end_date", "value_error")],
        ),
        (
            {**WEEKLY_THURSDAY, "starts_at": None, "ends_at": None},
            [("starts_at", "missing"), ("ends_at", "missing")],
        ),
        ({**WEEKLY_THURSDAY, "ends_at": "2026-10-01T16:00:00Z"}, [("ends_at", "value_error")]),
        ({**WEEKLY_THURSDAY, "ends_at": "2026-10-31T16:00:01Z"}, [("ends_at", "value_error")]),
        (
            {
                "kind": "one_time",
                "all_day": True,
                "start_date": "2026-10-01",
                "starts_at": "2026-10-01T10:00:00Z",
            },
            [("starts_at", "value_error")],
        ),
        ({"kind": "one_time", "all_day": True}, [("start_date", "missing")]),
        (
            {
                "kind": "one_time",
                "all_day": True,
                "start_date": "2026-10-02",
                "end_date": "2026-10-01",
            },
            [("end_date", "value_error")],
        ),
        (
            {
                "kind": "one_time",
                "all_day": True,
                "start_date": "2026-10-01",
                "end_date": "2026-10-31",
            },
            [("end_date", "value_error")],
        ),
        (
            {"kind": "birthday", "all_day": False, "start_date": "2000-05-05"},
            [("all_day", "value_error")],
        ),
        (
            {
                "kind": "birthday",
                "all_day": True,
                "start_date": "2000-05-05",
                "end_date": "2000-05-06",
            },
            [("end_date", "value_error")],
        ),
        (
            {
                "kind": "birthday",
                "all_day": True,
                "start_date": "2000-05-05",
                "rrule": "FREQ=MONTHLY",
            },
            [("rrule", "value_error")],
        ),
        (
            {"kind": "one_time", "all_day": True, "start_date": "0999-12-31"},
            [("start_date", "value_error")],
        ),
    ],
)
def test_write_rules(
    client: TestClient, crew: Crew, fields: dict[str, Any], expected: list[tuple[str, str]]
) -> None:
    response = crew.post(crew.alice, **fields)

    assert response.status_code == 422, response.text
    assert response.json()["code"] == "validation_error"
    assert errors(response) == expected


def test_a_30_day_event_is_allowed(client: TestClient, crew: Crew) -> None:
    timed = crew.post(
        crew.alice,
        **{**WEEKLY_THURSDAY, "kind": "one_time", "rrule": None, "ends_at": "2026-10-31T16:00:00Z"},
    )
    all_day = crew.post(
        crew.alice, kind="one_time", all_day=True, start_date="2026-10-01", end_date="2026-10-30"
    )

    assert timed.status_code == 201, timed.text
    assert all_day.status_code == 201, all_day.text


@pytest.mark.parametrize(
    ("fields", "field"),
    [
        ({"starts_at": "2026-10-01T19:00:00"}, "starts_at"),  # no offset
        ({"timezone": "Mars/Olympus"}, "timezone"),
        ({"title": ""}, "title"),
        ({"rrule": "FREQ=DAILY;" + "INTERVAL=1;" * 20}, "rrule"),
        ({"kind": "weekly"}, "kind"),
    ],
)
def test_schema_errors(client: TestClient, crew: Crew, fields: dict[str, Any], field: str) -> None:
    response = crew.post(crew.alice, **{**WEEKLY_THURSDAY, **fields})

    assert response.status_code == 422, response.text
    assert response.json()["code"] == "validation_error"
    assert [e["field"] for e in response.json()["errors"]] == [field]


@pytest.mark.parametrize(
    ("fields", "reason"),
    [
        (
            {
                "starts_at": "2026-10-31T16:00:00Z",
                "ends_at": "2026-10-31T18:00:00Z",
                "rrule": "FREQ=MONTHLY",
            },
            "monthly_day_over_28",
        ),
        ({"rrule": "FREQ=MONTHLY;BYDAY=-1FR;BYSETPOS=-1"}, "unsupported_part"),
        ({"rrule": "FREQ=WEEKLY;BYSETPOS=1"}, "unsupported_part"),
        ({"rrule": "FREQ=DAILY;UNTIL=20261001"}, "until_format"),
        (
            {
                "all_day": True,
                "starts_at": None,
                "ends_at": None,
                "start_date": "2028-02-29",
                "rrule": "FREQ=YEARLY",
            },
            "yearly_feb29",
        ),
    ],
)
def test_invalid_rrules(
    client: TestClient, crew: Crew, fields: dict[str, Any], reason: str
) -> None:
    response = crew.post(crew.alice, **{**WEEKLY_THURSDAY, **fields})

    assert response.status_code == 422, response.text
    body = response.json()
    assert body["code"] == "invalid_rrule"
    assert body["errors"][0]["field"] == "rrule"
    assert body["errors"][0]["type"] == reason


def test_references_must_be_in_the_group(client: TestClient, crew: Crew) -> None:
    other_owner = register(client)
    other = create_group(client, other_owner)
    foreign_category = list_categories(client, other_owner, other["id"])[0]
    foreign_activity = create_activity(client, other_owner, other["id"])

    for field, value in (
        ("category_id", foreign_category["id"]),
        ("activity_id", foreign_activity["id"]),
        ("category_id", "01890000-0000-7000-8000-000000000000"),
    ):
        response = crew.post(crew.alice, **WEEKLY_THURSDAY, **{field: value})
        assert response.status_code == 422, response.text
        assert response.json()["code"] == "invalid_reference"
        assert errors(response) == [(field, "invalid_reference")]


def test_color_is_the_effective_category_color(client: TestClient, crew: Crew) -> None:
    parent = create_category(client, crew.owner, crew.group_id, color="#AA0000")
    child = create_category(client, crew.owner, crew.group_id, parent_id=parent["id"])

    in_parent = crew.post(crew.alice, **WEEKLY_THURSDAY, category_id=parent["id"]).json()
    in_child = crew.post(crew.alice, **WEEKLY_THURSDAY, category_id=child["id"]).json()

    assert in_parent["color"] == "#AA0000"
    assert in_child["color"] == "#AA0000"  # inherited
    assert in_child["category_id"] == child["id"]


# --- scheduling ---------------------------------------------------------------------------


def test_an_event_linked_to_an_idea_schedules_it(
    client: TestClient, crew: Crew, db_session: Session
) -> None:
    idea = crew.activity(client, title="Escape room")
    done = crew.activity(client, status="done")

    event = crew.post(crew.alice, **WEEKLY_THURSDAY, activity_id=idea["id"]).json()
    crew.post(crew.alice, **WEEKLY_THURSDAY, activity_id=done["id"])

    activity = client.get(f"/api/v1/activities/{idea['id']}", headers=crew.alice.headers).json()
    assert activity["status"] == "scheduled"
    assert activity["version"] == idea["version"]  # a status change isn't a content change
    assert activity["events"] == [
        {
            "id": event["id"],
            "kind": "recurring",
            "title": "Game night",
            "all_day": False,
            "starts_at": "2026-10-01T16:00:00Z",
            "start_date": None,
            "rrule": "FREQ=WEEKLY;BYDAY=TH",
        }
    ]
    assert (
        client.get(f"/api/v1/activities/{done['id']}", headers=crew.alice.headers).json()["status"]
        == "done"
    )
    changes = db_session.scalars(
        select(GroupLog).where(GroupLog.action == "activity.status_changed")
    ).all()
    assert [(c.actor_id and str(c.actor_id), c.data) for c in changes] == [
        (crew.alice.id, {"from": "idea", "to": "scheduled", "via": "event"})
    ]


def test_linking_another_activity_in_a_put_schedules_it_and_unlinking_never_reverts(
    client: TestClient, crew: Crew
) -> None:
    first = crew.activity(client, status="planning")
    second = crew.activity(client, status="planning")
    event = crew.post(crew.owner, **WEEKLY_THURSDAY, activity_id=first["id"]).json()

    def status(activity: dict[str, Any]) -> str:
        body = client.get(f"/api/v1/activities/{activity['id']}", headers=crew.owner.headers)
        return str(body.json()["status"])

    # Back to planning by hand; re-sending the same link doesn't schedule it again.
    client.post(
        f"/api/v1/activities/{first['id']}/status",
        headers=crew.owner.headers,
        json={"status": "planning"},
    )
    event = crew.put(crew.owner, event, title="Renamed").json()
    assert status(first) == "planning"

    event = crew.put(crew.owner, event, activity_id=second["id"]).json()
    assert status(second) == "scheduled"

    event = crew.put(crew.owner, event, activity_id=None).json()
    assert status(second) == "scheduled"
    assert client.delete(url(event), headers=crew.owner.headers).status_code == 204
    assert status(second) == "scheduled"


def test_deleting_the_activity_unlinks_its_events(
    client: TestClient, crew: Crew, db_session: Session
) -> None:
    activity = crew.activity(client)
    event = crew.post(crew.owner, **WEEKLY_THURSDAY, activity_id=activity["id"]).json()

    assert (
        client.delete(
            f"/api/v1/activities/{activity['id']}", headers=crew.owner.headers
        ).status_code
        == 204
    )

    after = crew.get(crew.owner, event)
    assert after["activity_id"] is None
    assert after["version"] == event["version"] + 1


def test_deleting_a_category_moves_or_uncategorizes_events(client: TestClient, crew: Crew) -> None:
    parent = create_category(client, crew.owner, crew.group_id)
    child = create_category(client, crew.owner, crew.group_id, parent_id=parent["id"])
    in_child = crew.post(crew.owner, **WEEKLY_THURSDAY, category_id=child["id"]).json()
    in_parent = crew.post(crew.owner, **WEEKLY_THURSDAY, category_id=parent["id"]).json()

    client.delete(f"/api/v1/categories/{child['id']}", headers=crew.owner.headers)
    moved = crew.get(crew.owner, in_child)
    assert (moved["category_id"], moved["version"]) == (parent["id"], 2)

    client.delete(f"/api/v1/categories/{parent['id']}", headers=crew.owner.headers)
    assert (
        crew.get(crew.owner, in_child)["category_id"],
        crew.get(crew.owner, in_child)["version"],
    ) == (None, 3)
    assert crew.get(crew.owner, in_parent)["category_id"] is None


# --- next occurrence on activities --------------------------------------------------------


def test_next_occurrence_on_activity_cards(client: TestClient, crew: Crew) -> None:
    activity = crew.activity(client, title="Board games")
    other = crew.activity(client, title="Nothing planned")
    weekly = crew.post(crew.owner, **WEEKLY_THURSDAY, activity_id=activity["id"]).json()
    crew.post(
        crew.owner,
        kind="one_time",
        all_day=True,
        start_date="2026-10-10",
        activity_id=activity["id"],
    )

    def next_of(items: list[dict[str, Any]], activity_id: str) -> Any:
        return next(item for item in items if item["id"] == activity_id)["next_occurrence"]

    listing = f"/api/v1/groups/{crew.group_id}/activities"
    with signed_in_at(
        client, crew.owner, datetime(2026, 10, 8, 18, tzinfo=UTC)
    ) as headers:  # 21:00 local
        items = client.get(listing, headers=headers).json()["items"]
        detail = client.get(f"/api/v1/activities/{activity['id']}", headers=headers).json()
    assert next_of(items, activity["id"]) == {
        "event_id": weekly["id"],
        "occurrence_key": "20261008T160000Z",  # still running
        "all_day": False,
        "starts_at": "2026-10-08T16:00:00Z",
        "start_date": None,
    }
    assert detail["next_occurrence"] == next_of(items, activity["id"])
    assert next_of(items, other["id"]) is None

    # 9 October: the all-day one on the 10th comes before next Thursday.
    with signed_in_at(client, crew.owner, datetime(2026, 10, 9, 12, tzinfo=UTC)) as headers:
        items = client.get(listing, headers=headers).json()["items"]
    assert next_of(items, activity["id"])["occurrence_key"] == "20261010"
    assert next_of(items, activity["id"])["start_date"] == "2026-10-10"

    # A cancelled occurrence is skipped.
    client.delete(url(weekly, "/occurrences/20261015T160000Z"), headers=crew.owner.headers)
    with signed_in_at(client, crew.owner, datetime(2026, 10, 11, 12, tzinfo=UTC)) as headers:
        items = client.get(listing, headers=headers).json()["items"]
    assert next_of(items, activity["id"])["occurrence_key"] == "20261022T160000Z"


def test_an_all_day_occurrence_counts_until_the_end_of_its_last_day_in_the_group_zone(
    client: TestClient, crew: Crew
) -> None:
    activity = crew.activity(client)
    crew.post(
        crew.owner,
        kind="one_time",
        all_day=True,
        start_date="2026-10-10",
        activity_id=activity["id"],
    )
    path = f"/api/v1/activities/{activity['id']}"

    # 22:30Z on the 10th is already the 11th in Bucharest.
    with signed_in_at(client, crew.owner, datetime(2026, 10, 10, 20, 30, tzinfo=UTC)) as headers:
        assert client.get(path, headers=headers).json()["next_occurrence"] is not None
    with signed_in_at(client, crew.owner, datetime(2026, 10, 10, 22, 30, tzinfo=UTC)) as headers:
        assert client.get(path, headers=headers).json()["next_occurrence"] is None


# --- reading and updating -----------------------------------------------------------------


def test_put_replaces_the_series_and_bumps_the_version(
    client: TestClient, crew: Crew, db_session: Session
) -> None:
    event = crew.post(crew.alice, **WEEKLY_THURSDAY).json()

    response = crew.put(
        crew.alice, event, title="Board games", rrule="FREQ=WEEKLY;BYDAY=FR,TH", timezone="UTC"
    )

    assert response.status_code == 200, response.text
    updated = response.json()
    assert (updated["title"], updated["rrule"], updated["timezone"], updated["version"]) == (
        "Board games",
        "FREQ=WEEKLY;BYDAY=TH,FR",
        "UTC",
        2,
    )
    logs = db_session.scalars(select(GroupLog.data).where(GroupLog.action == "event.updated")).all()
    assert logs == [{"title": "Board games", "kind": "recurring"}]

    # The same content again still bumps the version, but logs nothing.
    again = crew.put(crew.alice, updated)
    assert again.json()["version"] == 3
    assert (
        len(db_session.scalars(select(GroupLog.id).where(GroupLog.action == "event.updated")).all())
        == 1
    )


def test_a_stale_version_is_a_conflict(client: TestClient, crew: Crew) -> None:
    event = crew.post(crew.alice, **WEEKLY_THURSDAY).json()
    crew.put(crew.alice, event, title="First")

    response = crew.put(crew.alice, event, title="Second")

    assert response.status_code == 409
    assert response.json()["code"] == "version_conflict"
    assert crew.get(crew.alice, event)["title"] == "First"


def test_a_put_can_change_the_kind_and_timing(
    client: TestClient, crew: Crew, db_session: Session
) -> None:
    event = crew.post(crew.alice, **WEEKLY_THURSDAY).json()

    response = crew.put(
        crew.alice,
        event,
        kind="one_time",
        all_day=True,
        starts_at=None,
        ends_at=None,
        start_date="2026-12-24",
        end_date="2026-12-26",
        rrule=None,
    )

    assert response.status_code == 200, response.text
    row = db_session.scalars(select(Event)).one()
    assert (row.kind, row.rrule, row.start_date.isoformat() if row.start_date else None) == (
        "one_time",
        None,
        "2026-12-24",
    )
    assert row.window_end == datetime(2026, 12, 27, 14, tzinfo=UTC)


def test_timing_changes_clear_the_exceptions_and_end_changes_keep_them(
    client: TestClient, crew: Crew
) -> None:
    event = crew.post(crew.alice, **WEEKLY_THURSDAY).json()
    client.delete(url(event, "/occurrences/20261008T160000Z"), headers=crew.alice.headers)
    client.delete(url(event, "/occurrences/20261001T160000Z"), headers=crew.alice.headers)
    event = crew.get(crew.alice, event)
    assert event["cancelled_occurrence_keys"] == ["20261001T160000Z", "20261008T160000Z"]

    event = crew.put(crew.alice, event, ends_at="2026-10-01T20:00:00Z", title="Longer").json()
    assert event["cancelled_occurrence_keys"] == ["20261001T160000Z", "20261008T160000Z"]

    for changes, next_key in (
        ({"rrule": "FREQ=WEEKLY;BYDAY=TH;COUNT=10"}, "20261008T160000Z"),
        ({"timezone": "UTC"}, "20261008T160000Z"),
        ({"starts_at": "2026-10-01T15:00:00Z"}, "20261008T150000Z"),
        (
            {
                "all_day": True,
                "starts_at": None,
                "ends_at": None,
                "start_date": "2026-10-01",
                "end_date": None,
            },
            "20261008",
        ),
    ):
        event = crew.put(crew.alice, event, **changes).json()
        assert event["cancelled_occurrence_keys"] == [], changes
        cancel = client.delete(url(event, f"/occurrences/{next_key}"), headers=crew.alice.headers)
        assert cancel.status_code == 204, (changes, cancel.text)
        event = crew.get(crew.alice, event)
        assert event["cancelled_occurrence_keys"] == [next_key]


def test_delete_event(client: TestClient, crew: Crew, db_session: Session) -> None:
    event = crew.post(crew.alice, **WEEKLY_THURSDAY).json()
    client.delete(url(event, "/occurrences/20261008T160000Z"), headers=crew.alice.headers)

    assert client.delete(url(event), headers=crew.alice.headers).status_code == 204

    assert client.get(url(event), headers=crew.alice.headers).status_code == 404
    assert db_session.scalar(select(EventException.id)) is None
    deleted = db_session.scalars(
        select(GroupLog.data).where(GroupLog.action == "event.deleted")
    ).all()
    assert deleted == [{"title": "Game night", "kind": "recurring"}]


# --- cancelling and restoring occurrences -------------------------------------------------


def test_cancel_and_restore_one_occurrence(
    client: TestClient, crew: Crew, db_session: Session
) -> None:
    event = crew.post(crew.alice, **WEEKLY_THURSDAY).json()
    key = "20261029T170000Z"  # after the DST change: 19:00 local is 17:00Z
    cancel = url(event, f"/occurrences/{key}")

    assert client.delete(cancel, headers=crew.alice.headers).status_code == 204
    assert client.delete(cancel, headers=crew.alice.headers).status_code == 204  # idempotent
    assert crew.get(crew.alice, event)["cancelled_occurrence_keys"] == [key]

    restore = url(event, f"/occurrences/{key}/restore")
    assert client.post(restore, headers=crew.alice.headers).status_code == 204
    assert client.post(restore, headers=crew.alice.headers).status_code == 204  # idempotent
    assert crew.get(crew.alice, event)["cancelled_occurrence_keys"] == []

    rows = db_session.execute(
        select(GroupLog.action, GroupLog.data)
        .where(GroupLog.action.like("event.occurrence_%"))
        .order_by(GroupLog.id)
    ).all()
    assert [tuple(row) for row in rows] == [
        ("event.occurrence_cancelled", {"occurrence_key": key}),
        ("event.occurrence_restored", {"occurrence_key": key}),
    ]


@pytest.mark.parametrize(
    ("key", "status"),
    [
        ("20261029T160000Z", 404),  # 19:00 local before the change, not after
        ("20261030T170000Z", 404),  # a Friday
        ("20260924T160000Z", 404),  # before the start
        ("20261029", 404),  # a date key on a timed event
        ("2026-10-29", 422),
        ("20261029T170000", 422),
        ("20261329T170000Z", 422),
        ("x" * 30, 422),
    ],
)
def test_cancel_needs_a_real_occurrence(
    client: TestClient, crew: Crew, key: str, status: int
) -> None:
    event = crew.post(crew.alice, **WEEKLY_THURSDAY).json()

    response = client.delete(url(event, f"/occurrences/{key}"), headers=crew.alice.headers)

    assert response.status_code == status, response.text
    if status == 422:
        assert response.json()["code"] == "validation_error"
        assert errors(response) == [("path.occurrence_key", "value_error")]
    else:
        assert response.json()["code"] == "not_found"


def test_all_day_and_birthday_occurrences(client: TestClient, crew: Crew) -> None:
    weekend = crew.post(
        crew.alice,
        kind="recurring",
        all_day=True,
        start_date="2026-10-03",
        end_date="2026-10-04",
        rrule="FREQ=WEEKLY",
    ).json()
    grandma = crew.post(
        crew.alice, kind="birthday", title="Grandma", all_day=True, start_date="2028-02-29"
    ).json()

    assert weekend["rrule"] == "FREQ=WEEKLY;BYDAY=SA"
    assert (
        client.delete(url(weekend, "/occurrences/20261010"), headers=crew.alice.headers).status_code
        == 204
    )
    assert (
        client.delete(url(weekend, "/occurrences/20261011"), headers=crew.alice.headers).status_code
        == 404
    )
    assert (
        client.delete(url(grandma, "/occurrences/20290228"), headers=crew.alice.headers).status_code
        == 204
    )
    assert (
        client.delete(url(grandma, "/occurrences/20290301"), headers=crew.alice.headers).status_code
        == 404
    )


def test_a_one_time_event_has_nothing_to_cancel(client: TestClient, crew: Crew) -> None:
    event = crew.post(crew.alice, kind="one_time", all_day=True, start_date="2026-10-03").json()

    response = client.delete(url(event, "/occurrences/20261003"), headers=crew.alice.headers)
    restore = client.post(url(event, "/occurrences/20261003/restore"), headers=crew.alice.headers)
    malformed = client.post(
        url(event, "/occurrences/2026-10-03/restore"), headers=crew.alice.headers
    )

    assert response.status_code == 422
    assert errors(response) == [("path.occurrence_key", "value_error")]
    assert restore.status_code == 204
    assert malformed.status_code == 422
    assert errors(malformed) == [("path.occurrence_key", "value_error")]


# --- permissions --------------------------------------------------------------------------


def test_who_may_edit_an_event(client: TestClient, crew: Crew) -> None:
    owned_activity = crew.activity(client)
    client.put(
        f"/api/v1/activities/{owned_activity['id']}",
        headers=crew.owner.headers,
        json={
            "title": owned_activity["title"],
            "owner_id": crew.bob.id,
            "version": owned_activity["version"],
        },
    )
    by_alice = crew.post(crew.alice, **WEEKLY_THURSDAY).json()
    bobs_activity = crew.post(
        crew.owner, **WEEKLY_THURSDAY, activity_id=owned_activity["id"]
    ).json()

    def flags(account: Account, event: dict[str, Any]) -> tuple[bool, bool]:
        body = crew.get(account, event)
        return body["can_edit"], body["can_delete"]

    assert flags(crew.alice, by_alice) == (True, True)  # creator
    assert flags(crew.bob, by_alice) == (False, False)
    assert flags(crew.admin, by_alice) == (True, True)
    assert flags(crew.bob, bobs_activity) == (True, True)  # the linked activity's owner
    assert flags(crew.alice, bobs_activity) == (False, False)

    key = "/occurrences/20261008T160000Z"
    for request in (
        lambda: crew.put(crew.bob, by_alice, title="Mine now"),
        lambda: client.delete(url(by_alice), headers=crew.bob.headers),
        lambda: client.delete(url(by_alice, key), headers=crew.bob.headers),
        lambda: client.post(url(by_alice, key + "/restore"), headers=crew.bob.headers),
    ):
        response = request()
        assert response.status_code == 403, response.text
        assert response.json()["code"] == "forbidden"

    assert crew.put(crew.bob, bobs_activity, title="Bob's").status_code == 200
    assert client.delete(url(by_alice, key), headers=crew.admin.headers).status_code == 204
    assert client.delete(url(by_alice), headers=crew.admin.headers).status_code == 204


def test_non_members_get_404_on_everything(client: TestClient, crew: Crew) -> None:
    event = crew.post(crew.alice, **WEEKLY_THURSDAY).json()
    outsider = register(client)
    key = "/occurrences/20261008T160000Z"

    for response in (
        client.get(url(event), headers=outsider.headers),
        client.put(url(event), headers=outsider.headers, json=event_update(event)),
        client.delete(url(event), headers=outsider.headers),
        client.delete(url(event, key), headers=outsider.headers),
        client.delete(url(event, "/occurrences/malformed"), headers=outsider.headers),
        client.post(url(event, key + "/restore"), headers=outsider.headers),
        client.post(
            f"/api/v1/groups/{crew.group_id}/events",
            headers=outsider.headers,
            json=WEEKLY_THURSDAY | {"title": "x"},
        ),
        client.get(
            f"/api/v1/groups/{crew.group_id}/calendar",
            headers=outsider.headers,
            params={"from": "2026-10-01", "to": "2026-11-01"},
        ),
        client.get(
            "/api/v1/events/01890000-0000-7000-8000-000000000000", headers=crew.alice.headers
        ),
    ):
        assert response.status_code == 404, response.text
        assert response.json()["code"] == "not_found"
    assert crew.get(crew.alice, event)["version"] == 1


def test_a_group_deletion_removes_its_events(
    client: TestClient, crew: Crew, db_session: Session
) -> None:
    event = crew.post(crew.alice, **WEEKLY_THURSDAY).json()
    client.delete(url(event, "/occurrences/20261008T160000Z"), headers=crew.alice.headers)

    assert (
        client.delete(f"/api/v1/groups/{crew.group_id}", headers=crew.owner.headers).status_code
        == 204
    )

    assert db_session.scalar(select(Event.id)) is None
    assert db_session.scalar(select(EventException.id)) is None
    assert db_session.scalar(select(Activity.id)) is None


def test_the_default_weekday_is_the_local_start_day(client: TestClient, crew: Crew) -> None:
    event = crew.post(
        crew.alice,
        **{**WEEKLY_THURSDAY, "rrule": "FREQ=WEEKLY"},
        timezone="Pacific/Kiritimati",
    ).json()

    # The default weekday is the start's local one: 16:00Z is Friday 06:00 in UTC+14.
    assert event["rrule"] == "FREQ=WEEKLY;BYDAY=FR"
    assert event["starts_at"] == "2026-10-01T16:00:00Z"
    assert timedelta(hours=3) == datetime.fromisoformat(event["ends_at"]) - datetime.fromisoformat(
        event["starts_at"]
    )
