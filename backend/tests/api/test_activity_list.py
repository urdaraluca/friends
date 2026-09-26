import base64
import uuid
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from datetime import datetime
from typing import Any

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import event

from friends_api.core.pagination import encode_cursor
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
Params = list[tuple[str, Any]]


def list_page(client: TestClient, account: Account, group_id: str, params: Params) -> Any:
    return client.get(
        f"/api/v1/groups/{group_id}/activities", headers=account.headers, params=params
    )


def list_all(
    client: TestClient, account: Account, group_id: str, params: Params, *, limit: int = 50
) -> list[dict[str, Any]]:
    """Every page, following next_cursor."""
    items: list[dict[str, Any]] = []
    cursor: str | None = None
    while True:
        page_params = [*params, ("limit", limit)] + ([("cursor", cursor)] if cursor else [])
        response = list_page(client, account, group_id, page_params)
        assert response.status_code == 200, response.text
        body = response.json()
        assert len(body["items"]) <= limit
        items += body["items"]
        cursor = body["next_cursor"]
        if cursor is None:
            return items


class Backlog:
    """Six activities with known properties in a EUR group."""

    def __init__(self, client: TestClient) -> None:
        self.owner = register(client)
        self.group = create_group(client, self.owner)
        self.alice = add_member(client, self.owner, self.group["id"])
        self.bob = add_member(client, self.owner, self.group["id"])
        categories = {c["name"]: c for c in list_categories(client, self.owner, self.group["id"])}
        movies, games = categories["Movie night"], categories["Games"]
        self.movies_id, self.games_id = movies["id"], games["id"]
        self.classics_id = create_category(
            client, self.owner, self.group["id"], name="Classics", parent_id=movies["id"]
        )["id"]
        gid = self.group["id"]

        def make(name: str, account: Account, **fields: Any) -> str:
            return str(create_activity(client, account, gid, title=name, **fields)["id"])

        self.ids = {
            "a1": make(
                "Alpha picnic",
                self.owner,
                status="idea",
                category_id=movies["id"],
                owner_id=self.alice.id,
                estimated_cost=10,
                due_date="2026-10-10",
            ),
            "a2": make(
                "Beta 100% fun",
                self.owner,
                status="planning",
                category_id=self.classics_id,
                owner_id=self.bob.id,
                estimated_cost=50,
                due_date="2026-10-20",
            ),
            "a3": make(
                "gamma_night",
                self.alice,
                status="scheduled",
                category_id=games["id"],
                estimated_cost=30,
                currency="RON",
            ),
            "a4": make("Delta", self.alice, status="done", due_date="2026-10-05"),
            "a5": make(
                "Epsilon",
                self.owner,
                status="dropped",
                category_id=movies["id"],
                estimated_cost=5,
            ),
            "a6": make("Zeta alpha", self.bob, status="idea"),
        }
        # a3 becomes unowned (the creator owns it by default).
        a3 = client.get(f"/api/v1/activities/{self.ids['a3']}", headers=self.alice.headers).json()
        client.put(
            f"/api/v1/activities/{self.ids['a3']}",
            headers=self.alice.headers,
            json=activity_update(a3, owner_id=None),
        )
        client.put(f"/api/v1/activities/{self.ids['a1']}/interest", headers=self.bob.headers)
        client.put(f"/api/v1/activities/{self.ids['a4']}/interest", headers=self.bob.headers)
        # Interests: owner a1 a2 a5; alice a3 a4; bob a1 a4 a6.

    def names(self, client: TestClient, params: Params) -> set[str]:
        items = list_all(client, self.owner, self.group["id"], params)
        by_id = {v: k for k, v in self.ids.items()}
        return {by_id[item["id"]] for item in items}


@pytest.fixture
def backlog(client: TestClient) -> Backlog:
    return Backlog(client)


def every_status(*params: tuple[str, Any]) -> Params:
    return [("status", s) for s in ALL_STATUSES] + list(params)


FILTER_CASES: list[tuple[str, Callable[[Backlog], Params], set[str]]] = [
    ("default statuses", lambda b: [], {"a1", "a2", "a3", "a6"}),
    ("archive", lambda b: [("status", "done"), ("status", "dropped")], {"a4", "a5"}),
    ("one status", lambda b: [("status", "planning")], {"a2"}),
    (
        "category with subcategories",
        lambda b: every_status(("category_id", b.movies_id)),
        {"a1", "a2", "a5"},
    ),
    (
        "category only",
        lambda b: every_status(("category_id", b.movies_id), ("include_subcategories", "false")),
        {"a1", "a5"},
    ),
    ("subcategory", lambda b: every_status(("category_id", b.classics_id)), {"a2"}),
    ("unknown category", lambda b: every_status(("category_id", str(uuid.uuid4()))), set()),
    ("owner", lambda b: every_status(("owner_id", b.alice.id)), {"a1", "a4"}),
    ("owner (creator by default)", lambda b: every_status(("owner_id", b.bob.id)), {"a2", "a6"}),
    ("interested", lambda b: every_status(("interested_by", b.bob.id)), {"a1", "a4", "a6"}),
    ("interested (creator)", lambda b: every_status(("interested_by", b.alice.id)), {"a3", "a4"}),
    ("unknown user", lambda b: every_status(("interested_by", str(uuid.uuid4()))), set()),
    (
        "cost with unpriced",
        lambda b: every_status(("cost_max", 30)),
        {"a1", "a3", "a4", "a5", "a6"},
    ),
    (
        "cost without unpriced",
        lambda b: every_status(("cost_max", 30), ("include_unpriced", "false")),
        {"a1", "a5"},
    ),
    (
        "cost is inclusive",
        lambda b: every_status(("cost_max", 10), ("include_unpriced", "false")),
        {"a1", "a5"},
    ),
    (
        "huge cost_max",
        lambda b: every_status(("cost_max", 10**30), ("include_unpriced", "false")),
        {"a1", "a2", "a5"},
    ),
    ("due before (inclusive)", lambda b: every_status(("due_before", "2026-10-10")), {"a1", "a4"}),
    (
        "due before as a midnight date-time",
        lambda b: every_status(("due_before", "2026-10-09T00:00:00.000Z")),
        {"a4"},
    ),
    ("title search ignores case", lambda b: every_status(("q", "ALPHA")), {"a1", "a6"}),
    ("% is literal", lambda b: every_status(("q", "100%")), {"a2"}),
    ("_ is literal", lambda b: every_status(("q", "_")), {"a3"}),
    ("no match", lambda b: every_status(("q", "nothing like this")), set()),
    (
        "combined",
        lambda b: every_status(("category_id", b.movies_id), ("interested_by", b.bob.id)),
        {"a1"},
    ),
]


@pytest.mark.parametrize(
    ("params", "expected"), [c[1:] for c in FILTER_CASES], ids=[c[0] for c in FILTER_CASES]
)
def test_filters_return_exactly_the_expected_activities(
    client: TestClient,
    backlog: Backlog,
    params: Callable[[Backlog], Params],
    expected: set[str],
) -> None:
    assert backlog.names(client, params(backlog)) == expected


@pytest.mark.parametrize(
    ("params", "field"),
    [
        ([("status", "someday")], "query.status.0"),
        ([("cost_max", -1)], "query.cost_max"),
        ([("due_before", "2026-10-10T12:00:00Z")], "query.due_before"),
        ([("due_before", "2026-10-10T00:00:00+02:00")], "query.due_before"),
        ([("q", "")], "query.q"),
        ([("q", "x" * 101)], "query.q"),
        ([("sort", "popularity")], "query.sort"),
        ([("order", "up")], "query.order"),
        ([("limit", 0)], "query.limit"),
        ([("limit", 101)], "query.limit"),
        ([("cursor", "not-a-cursor")], "query.cursor"),
        ([("cursor", encode_cursor(10**30))], "query.cursor"),  # too large to bind
        (
            [("cursor", base64.urlsafe_b64encode(b"[" * 20_000).decode())],  # deep nesting: no 500
            "query.cursor",
        ),
        ([("category_id", "123")], "query.category_id"),
    ],
)
def test_invalid_query_parameters(
    client: TestClient, backlog: Backlog, params: Params, field: str
) -> None:
    response = list_page(client, backlog.owner, backlog.group["id"], params)

    assert response.status_code == 422
    assert response.json()["code"] == "validation_error"
    assert response.json()["errors"][0]["field"] == field


def test_the_summary_shows_interest_and_ownership_from_the_callers_view(
    client: TestClient, backlog: Backlog
) -> None:
    items = {i["id"]: i for i in list_all(client, backlog.bob, backlog.group["id"], every_status())}

    a1 = items[backlog.ids["a1"]]
    assert (a1["interest_count"], a1["i_am_interested"]) == (2, True)
    assert a1["owner"]["id"] == backlog.alice.id
    assert (a1["can_edit"], a1["can_delete"]) == (True, False)
    assert items[backlog.ids["a3"]]["owner"] is None
    assert items[backlog.ids["a3"]]["currency"] == "RON"
    assert items[backlog.ids["a6"]]["can_delete"] is True  # bob created it


# --- sorting and paging -------------------------------------------------------------------

TITLES = ["Apple", "apple", "APPLE pie", "Banana", "banana split", "Cherry", "cherry", "Date"]
SORTS = ["created_at", "due_date", "title", "interest_count", "estimated_cost"]


def make_backlog(client: TestClient, size: int) -> tuple[Account, str]:
    """``size`` activities with ties and nulls in every sort key."""
    owner = register(client)
    group = create_group(client, owner, seed_default_categories=False)
    alice = add_member(client, owner, group["id"])
    bob = add_member(client, owner, group["id"])
    for i in range(size):
        activity = create_activity(
            client,
            owner,
            group["id"],
            title=f"{TITLES[i % len(TITLES)]} {i % 5}",
            status=ALL_STATUSES[i % 5],
            due_date=None if i % 3 == 0 else f"2026-11-{1 + i % 7:02d}",
            estimated_cost=None if i % 4 == 0 else (i % 6) * 10,
        )
        for account, every in ((alice, 3), (bob, 5)):
            if i % every == 0:
                client.put(f"/api/v1/activities/{activity['id']}/interest", headers=account.headers)
    return owner, group["id"]


def expected_order(items: list[dict[str, Any]], sort: str, order: str) -> list[str]:
    """The contract's ordering: nulls last for due date and cost, NOCASE titles, ties by id
    descending."""
    keys: dict[str, Callable[[dict[str, Any]], Any]] = {
        "created_at": lambda a: datetime.fromisoformat(a["created_at"]),
        "due_date": lambda a: a["due_date"],
        "title": lambda a: a["title"].lower(),
        "interest_count": lambda a: a["interest_count"],
        "estimated_cost": lambda a: a["estimated_cost"],
    }
    key = keys[sort]
    by_id = sorted(items, key=lambda a: uuid.UUID(a["id"]), reverse=True)
    present = [a for a in by_id if key(a) is not None]
    missing = [a for a in by_id if key(a) is None]
    present.sort(key=key, reverse=order == "desc")  # stable: ties keep id descending
    return [a["id"] for a in present + missing]


def test_paging_through_120_rows_has_no_gaps_or_duplicates_for_every_sort(
    client: TestClient,
) -> None:
    owner, group_id = make_backlog(client, 120)

    for sort in SORTS:
        for order in ("asc", "desc"):
            params = every_status(("sort", sort), ("order", order))

            paged = list_all(client, owner, group_id, params, limit=7)
            whole = list_all(client, owner, group_id, params, limit=100)

            ids = [item["id"] for item in paged]
            assert len(ids) == 120, (sort, order)
            assert len(set(ids)) == 120, (sort, order)
            assert ids == [item["id"] for item in whole], (sort, order)
            assert ids == expected_order(paged, sort, order), (sort, order)

    newest_first = list_all(client, owner, group_id, every_status())
    assert [i["id"] for i in newest_first] == expected_order(newest_first, "created_at", "desc")


def test_a_page_has_next_cursor_until_the_last_one(client: TestClient) -> None:
    owner, group_id = make_backlog(client, 61)

    default_page = list_page(client, owner, group_id, every_status()).json()
    first = list_page(client, owner, group_id, every_status(("limit", 60))).json()
    last = list_page(
        client, owner, group_id, every_status(("limit", 60), ("cursor", first["next_cursor"]))
    ).json()
    past_the_end = list_page(
        client,
        owner,
        group_id,
        every_status(("cursor", "eyJvIjo1MDB9")),  # {"o":500}
    ).json()

    assert len(default_page["items"]) == 50
    assert len(first["items"]) == 60
    assert first["next_cursor"] is not None
    assert len(last["items"]) == 1
    assert last["next_cursor"] is None
    assert past_the_end == {"items": [], "next_cursor": None}


@contextmanager
def count_queries(app: FastAPI) -> Iterator[list[str]]:
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


def test_listing_uses_a_fixed_number_of_queries(app: FastAPI, client: TestClient) -> None:
    owner, group_id = make_backlog(client, 30)

    with count_queries(app) as small:
        list_page(client, owner, group_id, every_status(("limit", 2)))
    with count_queries(app) as large:
        list_page(client, owner, group_id, every_status(("limit", 30)))

    assert len(small) == len(large), large
