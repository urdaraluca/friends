"""The "What should we do?" wheel (contract sections 8.10 and 10)."""

import random
import uuid
from collections import Counter
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
import time_machine
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import event, func, select
from sqlalchemy.orm import Session

from friends_api.core.pagination import encode_cursor
from friends_api.features.group_log.models import GroupLog
from friends_api.features.groups import service as groups_service
from friends_api.features.wheel import policies
from friends_api.features.wheel import service as wheel_service
from friends_api.features.wheel.deps import get_wheel_rng
from friends_api.features.wheel.models import WheelSpin
from friends_api.features.wheel.schemas import SpinCreate, WheelFilters
from tests.factories import (
    Account,
    activity_update,
    add_member,
    create_activity,
    create_category,
    create_group,
    list_categories,
    register,
)

ALL_STATUSES = ["idea", "planning", "scheduled", "done", "dropped"]
Filters = dict[str, Any]


def candidates_url(group_id: str) -> str:
    return f"/api/v1/groups/{group_id}/wheel/candidates"


def spins_url(group_id: str) -> str:
    return f"/api/v1/groups/{group_id}/wheel/spins"


def accept_url(spin_id: str) -> str:
    return f"/api/v1/wheel/spins/{spin_id}/accept"


def as_query(filters: Filters) -> list[tuple[str, Any]]:
    """``WheelFilters`` as query parameters (repeated ``status``)."""
    params: list[tuple[str, Any]] = []
    for key, value in filters.items():
        if isinstance(value, list):
            params += [(key, item) for item in value]
        elif isinstance(value, bool):
            params.append((key, "true" if value else "false"))
        else:
            params.append((key, value))
    return params


def get_candidates(
    client: TestClient, account: Account, group_id: str, filters: Filters | None = None
) -> Any:
    return client.get(
        candidates_url(group_id), headers=account.headers, params=as_query(filters or {})
    )


def spin(client: TestClient, account: Account, group_id: str, **body: Any) -> Any:
    return client.post(spins_url(group_id), headers=account.headers, json={"filters": {}, **body})


def spun(client: TestClient, account: Account, group_id: str, **body: Any) -> dict[str, Any]:
    response = spin(client, account, group_id, **body)
    assert response.status_code == 201, response.text
    result: dict[str, Any] = response.json()
    return result


def accept(client: TestClient, account: Account, spin_id: str) -> Any:
    return client.post(accept_url(spin_id), headers=account.headers)


def get_activity(client: TestClient, account: Account, activity_id: str) -> dict[str, Any]:
    response = client.get(f"/api/v1/activities/{activity_id}", headers=account.headers)
    assert response.status_code == 200, response.text
    body: dict[str, Any] = response.json()
    return body


def candidate_ids(spin_body: dict[str, Any]) -> list[str]:
    return [candidate["id"] for candidate in spin_body["candidates"]]


@pytest.fixture
def seed_rng(app: FastAPI) -> Iterator[Callable[[int], None]]:
    """Makes the server pick with ``random.Random(seed)``."""

    def use(seed: int) -> None:
        rng = random.Random(seed)
        app.dependency_overrides[get_wheel_rng] = lambda: rng

    yield use
    app.dependency_overrides.pop(get_wheel_rng, None)


class Backlog:
    """Seven activities with known properties in a EUR group.

    ====  =========  ===============================  =====  ========  ==========  ==========
    name  status     category                         owner  cost      due         interested
    ====  =========  ===============================  =====  ========  ==========  ==========
    a1    idea       Movie night                      alice  10 EUR    2026-10-10  owner, bob
    a2    planning   Classics (sub of Movie night)    bob    50 EUR    2026-10-20  owner
    a3    scheduled  Games                            alice  30 RON    -           alice
    a4    done       -                                alice  -         2026-10-05  alice
    a5    dropped    Movie night                      owner  5 EUR     -           owner
    a6    idea       -                                bob    -         -           bob
    a7    planning   Games                            alice  20 EUR    2026-10-01  alice, bob
    ====  =========  ===============================  =====  ========  ==========  ==========
    """

    def __init__(self, client: TestClient) -> None:
        self.owner = register(client)
        self.group = create_group(client, self.owner)
        self.alice = add_member(client, self.owner, self.group["id"])
        self.bob = add_member(client, self.owner, self.group["id"])
        gid = self.group_id
        categories = {c["name"]: c for c in list_categories(client, self.owner, gid)}
        self.movies, self.games = categories["Movie night"], categories["Games"]
        # No color of its own: it inherits Movie night's.
        self.classics = create_category(
            client, self.owner, gid, name="Classics", parent_id=self.movies["id"]
        )

        def make(name: str, account: Account, **fields: Any) -> str:
            return str(create_activity(client, account, gid, title=name, **fields)["id"])

        self.ids = {
            "a1": make(
                "Alpha",
                self.owner,
                category_id=self.movies["id"],
                owner_id=self.alice.id,
                estimated_cost=10,
                due_date="2026-10-10",
            ),
            "a2": make(
                "Beta",
                self.owner,
                status="planning",
                category_id=self.classics["id"],
                owner_id=self.bob.id,
                estimated_cost=50,
                due_date="2026-10-20",
            ),
            "a3": make(
                "Gamma",
                self.alice,
                status="scheduled",
                category_id=self.games["id"],
                estimated_cost=30,
                currency="RON",
            ),
            "a4": make("Delta", self.alice, status="done", due_date="2026-10-05"),
            "a5": make(
                "Epsilon",
                self.owner,
                status="dropped",
                category_id=self.movies["id"],
                estimated_cost=5,
            ),
            "a6": make("Zeta", self.bob),
            "a7": make(
                "Eta",
                self.alice,
                status="planning",
                category_id=self.games["id"],
                estimated_cost=20,
                due_date="2026-10-01",
            ),
        }
        for name in ("a1", "a7"):
            client.put(f"/api/v1/activities/{self.ids[name]}/interest", headers=self.bob.headers)

    @property
    def group_id(self) -> str:
        return str(self.group["id"])

    def names(self, ids: list[str]) -> list[str]:
        by_id = {v: k for k, v in self.ids.items()}
        return [by_id[activity_id] for activity_id in ids]


@pytest.fixture
def backlog(client: TestClient) -> Backlog:
    return Backlog(client)


# --- the candidate pool -------------------------------------------------------------------

FILTER_CASES: list[tuple[str, Callable[[Backlog], Filters], set[str]]] = [
    ("default statuses: idea and planning", lambda b: {}, {"a1", "a2", "a6", "a7"}),
    ("statuses", lambda b: {"status": ["scheduled", "done"]}, {"a3", "a4"}),
    ("one status", lambda b: {"status": ["planning"]}, {"a2", "a7"}),
    (
        "category with subcategories",
        lambda b: {"status": ALL_STATUSES, "category_id": b.movies["id"]},
        {"a1", "a2", "a5"},
    ),
    (
        "category only",
        lambda b: {
            "status": ALL_STATUSES,
            "category_id": b.movies["id"],
            "include_subcategories": False,
        },
        {"a1", "a5"},
    ),
    ("subcategory", lambda b: {"category_id": b.classics["id"]}, {"a2"}),
    ("interested by", lambda b: {"interested_by": b.bob.id}, {"a1", "a6", "a7"}),
    ("owner", lambda b: {"owner_id": b.alice.id}, {"a1", "a7"}),
    ("unknown owner", lambda b: {"owner_id": str(uuid.uuid4())}, set()),
    ("cost with unpriced", lambda b: {"cost_max": 20}, {"a1", "a6", "a7"}),
    (
        "cost without unpriced",
        lambda b: {"cost_max": 20, "include_unpriced": False},
        {"a1", "a7"},
    ),
    (
        "cost counts the group's currency only",
        lambda b: {"status": ["scheduled"], "cost_max": 1000, "include_unpriced": False},
        set(),
    ),
    ("due before (inclusive)", lambda b: {"due_before": "2026-10-10"}, {"a1", "a7"}),
    (
        "combined",
        lambda b: {"interested_by": b.bob.id, "category_id": b.games["id"]},
        {"a7"},
    ),
]


@pytest.mark.parametrize(
    ("filters", "expected"), [c[1:] for c in FILTER_CASES], ids=[c[0] for c in FILTER_CASES]
)
def test_candidates_and_spins_respect_the_filters(
    client: TestClient,
    backlog: Backlog,
    filters: Callable[[Backlog], Filters],
    expected: set[str],
) -> None:
    wanted = filters(backlog)

    listed = get_candidates(client, backlog.alice, backlog.group_id, wanted)
    spin_response = spin(client, backlog.alice, backlog.group_id, filters=wanted)

    assert listed.status_code == 200, listed.text
    body = listed.json()
    assert set(backlog.names([item["id"] for item in body["items"]])) == expected
    assert body["total"] == len(expected)
    if len(expected) >= 2:
        assert spin_response.status_code == 201, spin_response.text
        assert set(backlog.names(candidate_ids(spin_response.json()))) == expected
    else:
        assert spin_response.status_code == 422
        assert spin_response.json()["code"] == "not_enough_candidates"
        assert spin_response.json()["errors"] is None


def test_candidates_are_activity_summaries_newest_first(
    client: TestClient, backlog: Backlog
) -> None:
    items = get_candidates(client, backlog.bob, backlog.group_id).json()["items"]

    assert backlog.names([item["id"] for item in items]) == ["a7", "a6", "a2", "a1"]
    a1 = items[-1]
    assert (a1["title"], a1["status"], a1["category_id"]) == ("Alpha", "idea", backlog.movies["id"])
    assert (a1["interest_count"], a1["i_am_interested"]) == (2, True)
    assert a1["owner"]["id"] == backlog.alice.id
    assert (a1["can_edit"], a1["can_delete"]) == (True, False)


@pytest.mark.parametrize(
    ("params", "field"),
    [
        ([("status", "someday")], "query.status.0"),
        ([("status", s) for s in [*ALL_STATUSES, "idea"]], "query.status"),
        ([("category_id", "123")], "query.category_id"),
        ([("cost_max", -1)], "query.cost_max"),
        ([("due_before", "2026-10-10T12:00:00Z")], "query.due_before"),
    ],
)
def test_invalid_candidate_filters(
    client: TestClient, backlog: Backlog, params: list[tuple[str, Any]], field: str
) -> None:
    response = client.get(
        candidates_url(backlog.group_id), headers=backlog.owner.headers, params=params
    )

    assert response.status_code == 422
    assert response.json()["code"] == "validation_error"
    assert response.json()["errors"][0]["field"] == field


def make_pool(client: TestClient, size: int) -> tuple[Account, str, list[str]]:
    """``size`` ideas in a new group, and their IDs newest first (the slice order)."""
    owner = register(client)
    group = create_group(client, owner, seed_default_categories=False)
    ids = [create_activity(client, owner, group["id"])["id"] for _ in range(size)]
    create_activity(client, owner, group["id"], status="done")  # outside the default pool
    listed = client.get(
        f"/api/v1/groups/{group['id']}/activities",
        headers=owner.headers,
        params=[("status", "idea"), ("limit", 100)],
    ).json()["items"]
    pool = [item["id"] for item in listed]
    assert sorted(pool) == sorted(ids)
    return owner, group["id"], pool


def test_candidates_show_the_first_50_and_the_pool_size(client: TestClient) -> None:
    owner, group_id, pool = make_pool(client, 53)

    body = get_candidates(client, owner, group_id).json()

    assert body["total"] == 53
    assert [item["id"] for item in body["items"]] == pool[:50]


def test_a_pool_over_50_is_sampled_down_to_50(
    client: TestClient, seed_rng: Callable[[int], None]
) -> None:
    owner, group_id, pool = make_pool(client, 55)
    seed_rng(1234)

    body = spun(client, owner, group_id)

    expected_rng = random.Random(1234)
    chosen = set(expected_rng.sample(pool, 50))
    expected = [activity_id for activity_id in pool if activity_id in chosen]
    assert candidate_ids(body) == expected  # a uniform sample, still newest first
    assert expected != pool[:50]
    assert body["result_index"] == expected_rng.randrange(50)
    assert body["result"] == body["candidates"][body["result_index"]]
    assert body["result_activity_id"] == body["result"]["id"]


def test_spins_without_enough_candidates(client: TestClient, backlog: Backlog) -> None:
    empty_group = create_group(client, backlog.owner, seed_default_categories=False)
    one = spin(client, backlog.owner, backlog.group_id, filters={"status": ["done"]})
    none = spin(client, backlog.owner, empty_group["id"])
    hand_picked = [
        spin(client, backlog.owner, backlog.group_id, activity_ids=ids)
        for ids in ([], [backlog.ids["a1"]], [backlog.ids["a1"], backlog.ids["a1"]])
    ]

    for response in [one, none, *hand_picked]:
        assert response.status_code == 422, response.text
        assert response.json()["code"] == "not_enough_candidates"


# --- hand-picked candidates ---------------------------------------------------------------


def test_hand_picked_slices_keep_the_given_order_and_ignore_duplicates_and_filters(
    client: TestClient, backlog: Backlog
) -> None:
    ids = backlog.ids
    body = spun(
        client,
        backlog.alice,
        backlog.group_id,
        # a4 is done and a3 scheduled: the filters only describe the spin.
        filters={"status": ["dropped"], "owner_id": backlog.bob.id},
        activity_ids=[ids["a4"], ids["a1"], ids["a4"], ids["a3"], ids["a1"]],
    )

    assert backlog.names(candidate_ids(body)) == ["a4", "a1", "a3"]
    assert body["filters"]["status"] == ["dropped"]
    assert body["filters"]["owner_id"] == backlog.bob.id


def test_hand_picked_ids_must_be_activities_of_the_group(
    client: TestClient, backlog: Backlog
) -> None:
    other_group = create_group(client, backlog.owner)
    elsewhere = create_activity(client, backlog.owner, other_group["id"])["id"]
    ids = backlog.ids

    response = spin(
        client,
        backlog.owner,
        backlog.group_id,
        activity_ids=[ids["a1"], elsewhere, ids["a2"], str(uuid.uuid4()), elsewhere],
    )
    alone = spin(client, backlog.owner, backlog.group_id, activity_ids=[elsewhere])

    assert response.status_code == 422
    assert response.json()["code"] == "invalid_reference"
    assert [(e["field"], e["type"]) for e in response.json()["errors"]] == [
        ("activity_ids.1", "invalid_reference"),
        ("activity_ids.3", "invalid_reference"),
    ]
    assert alone.status_code == 422
    assert alone.json()["code"] == "invalid_reference"  # checked before the count


@pytest.mark.parametrize(
    ("body", "field"),
    [
        ({"activity_ids": [str(uuid.uuid4()) for _ in range(51)]}, "activity_ids"),
        ({"activity_ids": ["not-a-uuid"]}, "activity_ids.0"),
        ({"filters": {"status": []}}, "filters.status"),
        ({"filters": {"status": [*ALL_STATUSES, "idea"]}}, "filters.status"),
        ({"filters": {"status": ["someday"]}}, "filters.status.0"),
        ({"filters": {"cost_max": -1}}, "filters.cost_max"),
        ({"filters": {"due_before": "2026-10-10T21:00:00Z"}}, "filters.due_before"),
        ({"filters": None}, "filters"),
    ],
)
def test_invalid_spin_requests(
    client: TestClient, backlog: Backlog, body: dict[str, Any], field: str
) -> None:
    response = spin(client, backlog.owner, backlog.group_id, **body)

    assert response.status_code == 422
    assert response.json()["code"] == "validation_error"
    assert response.json()["errors"][0]["field"] == field


def test_the_filters_are_stored_normalized(client: TestClient, backlog: Backlog) -> None:
    body = spun(
        client,
        backlog.bob,
        backlog.group_id,
        filters={
            "status": ["planning", "scheduled", "idea", "planning"],
            "category_id": "",
            "interested_by": backlog.bob.id,
            "due_before": "2026-10-31T00:00:00.000Z",
            "unknown": "ignored",
        },
    )
    null_status = spun(client, backlog.bob, backlog.group_id, filters={"status": None})

    expected = {
        "status": ["idea", "planning", "scheduled"],
        "category_id": None,
        "include_subcategories": True,
        "interested_by": backlog.bob.id,
        "owner_id": None,
        "cost_max": None,
        "include_unpriced": True,
        "due_before": "2026-10-31",
    }
    assert body["filters"] == expected
    assert backlog.names(candidate_ids(body)) == ["a7", "a1"]
    listed = client.get(spins_url(backlog.group_id), headers=backlog.owner.headers).json()
    assert listed["items"][1]["filters"] == expected
    assert null_status["filters"]["status"] == ["idea", "planning"]  # null means the default


# --- the pick and the snapshot ------------------------------------------------------------


def test_the_server_picks_with_the_rng_and_logs_the_spin(
    client: TestClient,
    backlog: Backlog,
    seed_rng: Callable[[int], None],
    db_session: Session,
) -> None:
    ids = [backlog.ids[name] for name in ("a1", "a2", "a3", "a6")]
    seed_rng(99)

    body = spun(client, backlog.alice, backlog.group_id, activity_ids=ids)

    index = random.Random(99).randrange(4)
    assert body["result_index"] == index
    assert body["result"]["id"] == ids[index] == body["result_activity_id"]
    assert body["group_id"] == backlog.group_id
    assert body["spun_by"] == {
        "id": backlog.alice.id,
        "display_name": backlog.alice.body["user"]["display_name"],
        "avatar_url": None,
    }
    assert (body["accepted_at"], body["accepted_by"]) == (None, None)
    rows = db_session.execute(
        select(GroupLog.actor_id, GroupLog.subject_type, GroupLog.subject_id, GroupLog.data).where(
            GroupLog.action == "wheel.spun"
        )
    )
    assert [tuple(row) for row in rows] == [
        (
            uuid.UUID(backlog.alice.id),
            "spin",
            uuid.UUID(body["id"]),
            {"result_activity_id": ids[index], "candidate_count": 4},
        )
    ]


def test_the_snapshot_holds_the_effective_category_color(
    client: TestClient, backlog: Backlog
) -> None:
    ids = backlog.ids
    body = spun(
        client, backlog.owner, backlog.group_id, activity_ids=[ids["a1"], ids["a2"], ids["a6"]]
    )

    movie_color = backlog.movies["color"]
    assert movie_color is not None
    assert backlog.classics["color"] is None
    assert body["candidates"] == [
        {
            "id": ids["a1"],
            "title": "Alpha",
            "category_id": backlog.movies["id"],
            "color": movie_color,
        },
        {
            "id": ids["a2"],
            "title": "Beta",
            "category_id": backlog.classics["id"],
            "color": movie_color,  # inherited from its parent
        },
        {"id": ids["a6"], "title": "Zeta", "category_id": None, "color": None},
    ]


def test_history_keeps_the_snapshot_after_renames_and_deletions(
    client: TestClient, backlog: Backlog
) -> None:
    ids = backlog.ids
    body = spun(client, backlog.owner, backlog.group_id, activity_ids=[ids["a1"], ids["a2"]])
    picked = body["result_activity_id"]
    other = ids["a2"] if picked == ids["a1"] else ids["a1"]

    renamed = activity_update(get_activity(client, backlog.owner, other), title="Renamed")
    assert (
        client.put(f"/api/v1/activities/{other}", headers=backlog.owner.headers, json=renamed)
    ).status_code == 200
    recolored = {
        "name": backlog.movies["name"],
        "color": "#000000",
        "icon": backlog.movies["icon"],
        "position": backlog.movies["position"],
        "field_defs": backlog.movies["field_defs"],
    }
    assert (
        client.put(
            f"/api/v1/categories/{backlog.movies['id']}",
            headers=backlog.owner.headers,
            json=recolored,
        )
    ).status_code == 200
    assert (
        client.delete(f"/api/v1/activities/{picked}", headers=backlog.owner.headers)
    ).status_code == 204

    history = client.get(spins_url(backlog.group_id), headers=backlog.alice.headers).json()
    (after,) = history["items"]
    assert after["candidates"] == body["candidates"]
    assert after["result"] == body["result"]
    assert after["result_activity_id"] is None


# --- accepting ----------------------------------------------------------------------------


def test_accepting_moves_an_idea_to_planning(
    client: TestClient, backlog: Backlog, db_session: Session
) -> None:
    ids = backlog.ids
    body = spun(client, backlog.owner, backlog.group_id, activity_ids=[ids["a1"], ids["a6"]])
    picked = body["result_activity_id"]
    at = datetime.now(UTC).replace(microsecond=0) + timedelta(minutes=1)

    # Any member may accept, not only whoever spun.
    with time_machine.travel(at, tick=False):
        response = accept(client, backlog.bob, body["id"])

    assert response.status_code == 200, response.text
    accepted = response.json()
    assert datetime.fromisoformat(accepted["accepted_at"]) == at
    assert accepted["accepted_by"]["id"] == backlog.bob.id
    assert {k: v for k, v in accepted.items() if not k.startswith("accepted")} == {
        k: v for k, v in body.items() if not k.startswith("accepted")
    }
    activity = get_activity(client, backlog.owner, picked)
    assert activity["status"] == "planning"
    assert datetime.fromisoformat(activity["status_changed_at"]) == at
    assert activity["version"] == 1
    logged = db_session.execute(
        select(GroupLog.action, GroupLog.actor_id, GroupLog.subject_id, GroupLog.data)
        .where(GroupLog.action.in_(["wheel.accepted", "activity.status_changed"]))
        .order_by(GroupLog.id)
    )
    bob = uuid.UUID(backlog.bob.id)
    assert [tuple(row) for row in logged] == [
        ("wheel.accepted", bob, uuid.UUID(body["id"]), {"activity_id": picked}),
        (
            "activity.status_changed",
            bob,
            uuid.UUID(picked),
            {"from": "idea", "to": "planning", "via": "wheel"},
        ),
    ]


@pytest.mark.parametrize("names", [("a2", "a7"), ("a3", "a4")], ids=["planning", "later"])
def test_accepting_leaves_other_statuses(
    client: TestClient, backlog: Backlog, db_session: Session, names: tuple[str, str]
) -> None:
    ids = [backlog.ids[name] for name in names]
    body = spun(client, backlog.owner, backlog.group_id, activity_ids=ids)
    before = get_activity(client, backlog.owner, body["result_activity_id"])

    response = accept(client, backlog.alice, body["id"])

    assert response.status_code == 200, response.text
    after = get_activity(client, backlog.owner, body["result_activity_id"])
    assert after["status"] == before["status"]
    assert after["status_changed_at"] == before["status_changed_at"]
    actions = db_session.scalars(
        select(GroupLog.action).where(
            GroupLog.action.in_(["wheel.accepted", "activity.status_changed"])
        )
    ).all()
    assert list(actions) == ["wheel.accepted"]


def test_a_second_accept_changes_nothing(
    client: TestClient, backlog: Backlog, db_session: Session
) -> None:
    ids = backlog.ids
    body = spun(client, backlog.owner, backlog.group_id, activity_ids=[ids["a1"], ids["a6"]])
    first = accept(client, backlog.alice, body["id"]).json()

    again = accept(client, backlog.bob, body["id"])
    # Still unchanged once the activity is gone: the spin was already accepted.
    client.delete(f"/api/v1/activities/{body['result_activity_id']}", headers=backlog.owner.headers)
    after_deletion = accept(client, backlog.bob, body["id"])

    assert again.status_code == 200
    assert again.json() == first
    assert after_deletion.status_code == 200
    assert after_deletion.json() == {**first, "result_activity_id": None}
    accepted_logs = db_session.scalar(
        select(func.count()).where(GroupLog.action == "wheel.accepted")
    )
    assert accepted_logs == 1


def test_accepting_a_deleted_result_is_a_conflict(
    client: TestClient, backlog: Backlog, db_session: Session
) -> None:
    ids = backlog.ids
    body = spun(client, backlog.owner, backlog.group_id, activity_ids=[ids["a1"], ids["a6"]])
    client.delete(f"/api/v1/activities/{body['result_activity_id']}", headers=backlog.owner.headers)

    response = accept(client, backlog.alice, body["id"])

    assert response.status_code == 409
    assert response.json()["code"] == "result_deleted"
    stored = db_session.get_one(WheelSpin, uuid.UUID(body["id"]))
    assert (stored.accepted_at, stored.accepted_by_id, stored.result_activity_id) == (
        None,
        None,
        None,
    )


def test_unknown_spins_are_not_found(client: TestClient, backlog: Backlog) -> None:
    response = accept(client, backlog.owner, str(uuid.uuid4()))

    assert response.status_code == 404
    assert response.json()["code"] == "not_found"


def test_the_service_enforces_the_wheel_policies(
    client: TestClient, backlog: Backlog, monkeypatch: pytest.MonkeyPatch
) -> None:
    ids = [backlog.ids["a1"], backlog.ids["a6"]]
    body = spun(client, backlog.owner, backlog.group_id, activity_ids=ids)
    monkeypatch.setattr(policies, "can_spin", lambda actor: False)
    monkeypatch.setattr(policies, "can_accept_spin", lambda actor, spin: False)

    denied_spin = spin(client, backlog.alice, backlog.group_id, activity_ids=ids)
    denied_accept = accept(client, backlog.alice, body["id"])

    assert (denied_spin.status_code, denied_spin.json()["code"]) == (403, "forbidden")
    assert (denied_accept.status_code, denied_accept.json()["code"]) == (403, "forbidden")


# --- history ------------------------------------------------------------------------------


def test_history_is_newest_first_and_paginated(client: TestClient, backlog: Backlog) -> None:
    ids = [backlog.ids["a1"], backlog.ids["a6"]]
    made = [
        spun(client, account, backlog.group_id, activity_ids=ids)
        for account in (backlog.owner, backlog.alice, backlog.bob)
    ]
    accepted = accept(client, backlog.alice, made[0]["id"]).json()

    first = client.get(
        spins_url(backlog.group_id), headers=backlog.bob.headers, params={"limit": 2}
    ).json()
    second = client.get(
        spins_url(backlog.group_id),
        headers=backlog.bob.headers,
        params={"limit": 2, "cursor": first["next_cursor"]},
    ).json()
    everything = client.get(spins_url(backlog.group_id), headers=backlog.bob.headers).json()

    assert first["items"] == [made[2], made[1]]
    assert first["next_cursor"] is not None
    assert second == {"items": [accepted], "next_cursor": None}
    assert everything == {"items": [made[2], made[1], accepted], "next_cursor": None}
    assert accepted["accepted_by"]["id"] == backlog.alice.id
    assert [spin_body["spun_by"]["id"] for spin_body in everything["items"]] == [
        backlog.bob.id,
        backlog.alice.id,
        backlog.owner.id,
    ]


@pytest.mark.parametrize(
    ("params", "field"),
    [
        ({"cursor": "not-a-cursor"}, "query.cursor"),
        ({"cursor": encode_cursor(10**30)}, "query.cursor"),
        ({"limit": 0}, "query.limit"),
        ({"limit": 101}, "query.limit"),
    ],
)
def test_invalid_history_paging(
    client: TestClient, backlog: Backlog, params: dict[str, Any], field: str
) -> None:
    response = client.get(spins_url(backlog.group_id), headers=backlog.owner.headers, params=params)

    assert response.status_code == 422
    assert response.json()["errors"][0]["field"] == field


@contextmanager
def count_selects(app: FastAPI) -> Iterator[list[str]]:
    statements: list[str] = []

    def record(_conn: Any, _cursor: Any, statement: str, *_args: Any) -> None:
        if statement.lstrip().upper().startswith("SELECT"):
            statements.append(statement)

    engine = app.state.engine
    event.listen(engine, "before_cursor_execute", record)
    try:
        yield statements
    finally:
        event.remove(engine, "before_cursor_execute", record)


def test_history_uses_a_fixed_number_of_queries(
    app: FastAPI, client: TestClient, backlog: Backlog
) -> None:
    ids = [backlog.ids["a1"], backlog.ids["a6"]]
    for account in (backlog.owner, backlog.alice, backlog.bob, backlog.owner):
        body = spun(client, account, backlog.group_id, activity_ids=ids)
        accept(client, backlog.bob, body["id"])

    with count_selects(app) as small:
        client.get(spins_url(backlog.group_id), headers=backlog.owner.headers, params={"limit": 1})
    with count_selects(app) as large:
        client.get(spins_url(backlog.group_id), headers=backlog.owner.headers, params={"limit": 4})

    assert len(small) == len(large), large


def test_deleting_the_group_deletes_its_spins(
    client: TestClient, backlog: Backlog, db_session: Session
) -> None:
    spun(
        client, backlog.owner, backlog.group_id, activity_ids=[backlog.ids["a1"], backlog.ids["a6"]]
    )

    response = client.delete(f"/api/v1/groups/{backlog.group_id}", headers=backlog.owner.headers)

    assert response.status_code == 204
    assert db_session.scalar(select(func.count()).select_from(WheelSpin)) == 0


def test_the_status_default_is_not_declared_in_the_schema(client: TestClient) -> None:
    """swagger_parser turns an enum-list default into Dart that doesn't compile, so the server
    applies ``[idea, planning]`` when ``status`` is omitted or null."""
    schema = client.get("/api/v1/openapi.json").json()

    status = schema["components"]["schemas"]["WheelFilters"]["properties"]["status"]
    assert "default" not in status
    assert (status["minItems"], status["maxItems"]) == (1, 5)
    assert WheelFilters().status == WheelFilters.model_validate({"status": None}).status


# --- fairness -----------------------------------------------------------------------------


def test_every_slice_has_the_same_odds(client: TestClient, db_session: Session) -> None:
    """10 000 spins over 4 candidates with a seeded RNG land within 25% +- 5% each, through
    the real service: interest doesn't weigh (the first candidate has 3 interested members, the
    others 1)."""
    owner = register(client)
    group = create_group(client, owner, seed_default_categories=False)
    ids = [uuid.UUID(create_activity(client, owner, group["id"])["id"]) for _ in range(4)]
    for _ in range(2):
        member = add_member(client, owner, group["id"])
        client.put(f"/api/v1/activities/{ids[0]}/interest", headers=member.headers)
    access = groups_service.get_access(db_session, uuid.UUID(group["id"]), uuid.UUID(owner.id))
    assert access is not None
    rng = random.Random(20261001)
    body = SpinCreate(filters=WheelFilters(), activity_ids=ids)

    results = Counter(
        wheel_service.create_spin(db_session, access, body, rng=rng).result_activity_id
        for _ in range(10_000)
    )
    db_session.rollback()

    assert set(results) == set(ids)
    for activity_id in ids:
        assert 0.20 <= results[activity_id] / 10_000 <= 0.30, results
