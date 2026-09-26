import uuid
from typing import Any

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from friends_api.features.group_log.models import GroupLog
from tests.factories import (
    Account,
    add_member,
    create_activity,
    create_category,
    create_group,
    list_categories,
    register,
)

MOVIE_NIGHT_FIELD_DEFS = [
    {
        "key": "genre",
        "label": "Genre",
        "type": "select",
        "options": [
            "Action",
            "Comedy",
            "Drama",
            "Horror",
            "Sci-fi",
            "Animation",
            "Documentary",
            "Thriller",
            "Romance",
            "Other",
        ],
        "min": None,
        "max": None,
        "show_on_card": False,
    },
    {
        "key": "imdb_rating",
        "label": "IMDb rating",
        "type": "rating",
        "options": None,
        "min": 0,
        "max": 10,
        "show_on_card": True,
    },
    {
        "key": "imdb_url",
        "label": "IMDb link",
        "type": "url",
        "options": None,
        "min": None,
        "max": None,
        "show_on_card": False,
    },
    {
        "key": "year",
        "label": "Year",
        "type": "year",
        "options": None,
        "min": None,
        "max": None,
        "show_on_card": False,
    },
    {
        "key": "runtime_min",
        "label": "Runtime (min)",
        "type": "number",
        "options": None,
        "min": 1,
        "max": 600,
        "show_on_card": False,
    },
]

DEFAULTS = [
    ("Movie night", "#7E57C2", "movie"),
    ("Food & drinks", "#EF6C00", "food"),
    ("Outdoors", "#2E7D32", "outdoors"),
    ("Games", "#1565C0", "games"),
    ("Trips", "#00838F", "trips"),
    ("Culture", "#AD1457", "culture"),
    ("Sports", "#C62828", "sports"),
]


def field_def(key: str, type_: str = "text", **extra: Any) -> dict[str, Any]:
    return {"key": key, "label": key.title(), "type": type_, **extra}


def put_category(
    client: TestClient, account: Account, category: dict[str, Any], **changes: Any
) -> Any:
    body = {
        "name": category["name"],
        "parent_id": category["parent_id"],
        "color": category["color"],
        "icon": category["icon"],
        "position": category["position"],
        "field_defs": category["field_defs"],
        **changes,
    }
    return client.put(f"/api/v1/categories/{category['id']}", headers=account.headers, json=body)


def post_category(client: TestClient, account: Account, group_id: str, **body: Any) -> Any:
    return client.post(f"/api/v1/groups/{group_id}/categories", headers=account.headers, json=body)


@pytest.fixture
def owner(client: TestClient) -> Account:
    return register(client)


@pytest.fixture
def group(client: TestClient, owner: Account) -> dict[str, Any]:
    return create_group(client, owner, seed_default_categories=False)


# --- default seed -------------------------------------------------------------------------


def test_the_default_categories_match_the_contract_exactly(client: TestClient) -> None:
    owner = register(client)
    group = create_group(client, owner)

    categories = list_categories(client, owner, group["id"])

    assert [(c["name"], c["color"], c["icon"], c["position"]) for c in categories] == [
        (name, color, icon, position) for position, (name, color, icon) in enumerate(DEFAULTS)
    ]
    movie_night = categories[0]
    assert movie_night["field_defs"] == MOVIE_NIGHT_FIELD_DEFS
    assert movie_night["effective_field_defs"] == MOVIE_NIGHT_FIELD_DEFS
    for category in categories:
        assert category["parent_id"] is None
        assert category["subcategories"] == []
        assert category["effective_color"] == category["color"]
        assert category["created_by"]["id"] == owner.id
        assert category["can_edit"] is category["can_delete"] is True
        if category is not movie_night:
            assert category["field_defs"] == []


def test_each_default_category_is_logged_as_created(
    client: TestClient, db_session: Session
) -> None:
    owner = register(client)
    group = create_group(client, owner)
    categories = list_categories(client, owner, group["id"])

    rows = db_session.execute(
        select(GroupLog.actor_id, GroupLog.subject_id, GroupLog.data)
        .where(GroupLog.group_id == uuid.UUID(group["id"]), GroupLog.action == "category.created")
        .order_by(GroupLog.id)
    ).all()

    assert [(str(actor), str(subject), data) for actor, subject, data in rows] == [
        (owner.id, c["id"], {"name": c["name"]}) for c in categories
    ]


def test_no_defaults_when_seeding_is_off(
    client: TestClient, owner: Account, group: dict[str, Any], db_session: Session
) -> None:
    assert list_categories(client, owner, group["id"]) == []
    assert (
        db_session.scalar(select(GroupLog.id).where(GroupLog.action == "category.created")) is None
    )


# --- create, list, update -----------------------------------------------------------------


def test_create_and_list_categories_with_subcategories(
    client: TestClient, owner: Account, group: dict[str, Any]
) -> None:
    outdoors = create_category(
        client, owner, group["id"], name=" Outdoors ", color="#2e7d32", position=1
    )
    games = create_category(client, owner, group["id"], name="games", color="#1565C0", position=1)
    first = create_category(
        client, owner, group["id"], name="Zoo trips", color="#000000", position=0
    )
    hiking = create_category(
        client,
        owner,
        group["id"],
        name="Hiking",
        parent_id=outdoors["id"],
        field_defs=[field_def("distance_km", "number", min=0, max=100)],
        icon="🥾",
    )
    create_category(client, owner, group["id"], name="Cycling", parent_id=outdoors["id"])

    assert outdoors["name"] == "Outdoors"
    assert outdoors["color"] == "#2E7D32"
    assert hiking["color"] is None
    assert hiking["effective_color"] == "#2E7D32"  # inherited
    assert hiking["icon"] == "🥾"
    assert hiking["position"] == 0  # appended among its siblings
    categories = list_categories(client, owner, group["id"])
    # By position, then name (case-insensitively).
    assert [c["id"] for c in categories] == [first["id"], games["id"], outdoors["id"]]
    assert [s["name"] for s in categories[2]["subcategories"]] == ["Hiking", "Cycling"]
    assert [s["position"] for s in categories[2]["subcategories"]] == [0, 1]


def test_subcategories_inherit_the_parents_field_defs_first(
    client: TestClient, owner: Account, group: dict[str, Any]
) -> None:
    parent = create_category(
        client, owner, group["id"], field_defs=[field_def("a"), field_def("b")]
    )
    child = create_category(
        client, owner, group["id"], parent_id=parent["id"], field_defs=[field_def("c")]
    )

    assert [f["key"] for f in child["field_defs"]] == ["c"]
    assert [f["key"] for f in child["effective_field_defs"]] == ["a", "b", "c"]


def test_a_top_level_category_needs_a_color(
    client: TestClient, owner: Account, group: dict[str, Any]
) -> None:
    response = post_category(client, owner, group["id"], name="No color")

    assert response.status_code == 422
    assert response.json()["code"] == "validation_error"
    assert response.json()["errors"][0]["field"] == "color"


def test_a_blank_color_means_null(
    client: TestClient, owner: Account, group: dict[str, Any]
) -> None:
    """Contract 1.4: a blank optional string is null, not a pattern mismatch."""
    parent = create_category(client, owner, group["id"], color="#2E7D32", icon=" ")

    child = create_category(client, owner, group["id"], parent_id=parent["id"], color="")
    recolored = put_category(client, owner, child, color="  ")
    top_level = post_category(client, owner, group["id"], name="Top", color="")

    assert parent["icon"] is None
    assert (child["color"], child["effective_color"]) == (None, "#2E7D32")  # inherited
    assert recolored.status_code == 200, recolored.text
    assert recolored.json()["color"] is None
    assert top_level.status_code == 422  # still required at the top level
    assert [(e["field"], e["type"]) for e in top_level.json()["errors"]] == [("color", "missing")]


@pytest.mark.parametrize("position", [-1, 1_000_001, 2**63])
def test_positions_are_bounded(
    client: TestClient, owner: Account, group: dict[str, Any], position: int
) -> None:
    """Contract 1.9: 0..1,000,000, which also keeps SQLite's 64-bit integers from overflowing."""
    created = post_category(client, owner, group["id"], name="C", color="#000000", position=0)
    category = created.json()

    posted = post_category(client, owner, group["id"], name="D", color="#000000", position=position)
    updated = put_category(client, owner, category, position=position)

    for response in (posted, updated):
        assert response.status_code == 422, response.text
        assert response.json()["errors"][0]["field"] == "position"
    assert put_category(client, owner, category, position=1_000_000).status_code == 200


def test_appending_after_the_last_position_stays_in_range(
    client: TestClient, owner: Account, group: dict[str, Any]
) -> None:
    create_category(client, owner, group["id"], position=1_000_000)

    appended = create_category(client, owner, group["id"])

    assert appended["position"] == 1_000_000
    assert put_category(client, owner, appended).status_code == 200  # echoing it back is valid


def test_position_null_appends_on_create_and_keeps_on_update(
    client: TestClient, owner: Account, group: dict[str, Any]
) -> None:
    create_category(client, owner, group["id"], position=7)
    appended = create_category(client, owner, group["id"])
    assert appended["position"] == 8

    kept = put_category(client, owner, appended, position=None, name="Renamed")
    moved = put_category(client, owner, appended, position=2)

    assert kept.status_code == 200
    assert kept.json()["position"] == 8
    assert kept.json()["name"] == "Renamed"
    assert moved.json()["position"] == 2


def test_names_are_unique_among_siblings_ignoring_case(
    client: TestClient, owner: Account, group: dict[str, Any]
) -> None:
    movies = create_category(client, owner, group["id"], name="Movie night")
    outdoors = create_category(client, owner, group["id"], name="Outdoors")
    create_category(client, owner, group["id"], name="Classics", parent_id=movies["id"])

    top_clash = post_category(client, owner, group["id"], name="MOVIE night", color="#111111")
    sub_clash = post_category(client, owner, group["id"], name="classics", parent_id=movies["id"])
    other_parent = post_category(
        client, owner, group["id"], name="Classics", parent_id=outdoors["id"]
    )
    sub_named_like_a_top = post_category(
        client, owner, group["id"], name="Outdoors", parent_id=movies["id"]
    )
    rename_clash = put_category(client, owner, outdoors, name="movie NIGHT")

    for response in (top_clash, sub_clash, rename_clash):
        assert response.status_code == 409, response.text
        assert response.json()["code"] == "name_taken"
    assert other_parent.status_code == 201
    assert sub_named_like_a_top.status_code == 201
    assert put_category(client, owner, outdoors, name="OUTDOORS").status_code == 200  # itself


def test_categories_are_limited_to_100_per_group(client: TestClient) -> None:
    owner = register(client)
    group = create_group(client, owner)  # 7 defaults
    for i in range(93):
        create_category(client, owner, group["id"], name=f"C{i}")

    response = post_category(client, owner, group["id"], name="One too many", color="#000000")

    assert response.status_code == 422
    assert response.json()["code"] == "limit_reached"


# --- depth and references -----------------------------------------------------------------


def test_a_third_level_is_rejected(
    client: TestClient, owner: Account, group: dict[str, Any]
) -> None:
    parent = create_category(client, owner, group["id"])
    child = create_category(client, owner, group["id"], parent_id=parent["id"])

    response = post_category(client, owner, group["id"], name="Grandchild", parent_id=child["id"])

    assert response.status_code == 422
    assert response.json()["code"] == "category_depth_exceeded"
    assert response.json()["errors"][0]["field"] == "parent_id"


def test_moving_a_category_with_subcategories_under_a_parent_is_rejected(
    client: TestClient, owner: Account, group: dict[str, Any]
) -> None:
    parent = create_category(client, owner, group["id"])
    create_category(client, owner, group["id"], parent_id=parent["id"])
    other = create_category(client, owner, group["id"])
    child = create_category(client, owner, group["id"], parent_id=other["id"])

    has_children = put_category(client, owner, parent, parent_id=other["id"])
    under_a_subcategory = put_category(client, owner, other, parent_id=child["id"])

    assert has_children.status_code == 422
    assert has_children.json()["code"] == "category_depth_exceeded"
    assert under_a_subcategory.status_code == 422
    assert under_a_subcategory.json()["code"] == "category_depth_exceeded"


def test_moving_a_subcategory_and_promoting_it(
    client: TestClient, owner: Account, group: dict[str, Any]
) -> None:
    a = create_category(client, owner, group["id"], color="#AA0000")
    b = create_category(client, owner, group["id"], color="#00BB00")
    child = create_category(client, owner, group["id"], parent_id=a["id"])

    moved = put_category(client, owner, child, parent_id=b["id"])
    promoted_without_color = put_category(client, owner, child, parent_id=None)
    promoted = put_category(client, owner, child, parent_id=None, color="#0000CC")

    assert moved.status_code == 200
    assert moved.json()["effective_color"] == "#00BB00"
    assert promoted_without_color.status_code == 422
    assert promoted.status_code == 200
    assert promoted.json()["parent_id"] is None


def test_parents_must_exist_in_the_same_group(
    client: TestClient, owner: Account, group: dict[str, Any]
) -> None:
    other_group = create_group(client, owner, name="Other")
    foreign = create_category(client, owner, other_group["id"])
    category = create_category(client, owner, group["id"])

    foreign_parent = post_category(client, owner, group["id"], name="X", parent_id=foreign["id"])
    own_parent = put_category(client, owner, category, parent_id=category["id"])

    for response in (foreign_parent, own_parent):
        assert response.status_code == 422
        assert response.json()["code"] == "invalid_reference"
        assert response.json()["errors"][0]["field"] == "parent_id"


# --- field definitions (contract section 6.1) ---------------------------------------------


@pytest.mark.parametrize(
    ("field_defs", "field", "error_type"),
    [
        ([field_def("Genre")], "field_defs.0.key", "string_pattern_mismatch"),
        ([field_def("1st")], "field_defs.0.key", "string_pattern_mismatch"),
        ([field_def("a-b")], "field_defs.0.key", "string_pattern_mismatch"),
        ([field_def("k" * 31)], "field_defs.0.key", "string_pattern_mismatch"),
        ([{**field_def("ok"), "label": " "}], "field_defs.0.label", "string_too_short"),
        ([{**field_def("ok"), "label": "L" * 41}], "field_defs.0.label", "string_too_long"),
        ([field_def("ok", "boolean")], "field_defs.0.type", "enum"),
        ([field_def("ok", "select")], "field_defs.0.options", "missing"),
        ([field_def("ok", "select", options=[])], "field_defs.0.options", "too_short"),
        (
            [field_def("ok", "select", options=[f"o{i}" for i in range(31)])],
            "field_defs.0.options",
            "too_long",
        ),
        (
            [field_def("ok", "select", options=["x" * 41])],
            "field_defs.0.options.0",
            "string_too_long",
        ),
        ([field_def("ok", "select", options=["A", " a"])], "field_defs.0.options", "value_error"),
        ([field_def("ok", "text", options=["A"])], "field_defs.0.options", "value_error"),
        ([field_def("ok", "text", min=1)], "field_defs.0.min", "value_error"),
        ([field_def("ok", "url", max=1)], "field_defs.0.max", "value_error"),
        ([field_def("ok", "year", min=1900)], "field_defs.0.min", "value_error"),
        ([field_def("ok", "number", min=5, max=5)], "field_defs.0.max", "value_error"),
        ([field_def("ok", "rating", max=11)], "field_defs.0.max", "value_error"),
        ([field_def("ok", "rating", min=-1)], "field_defs.0.min", "value_error"),
        ([field_def("ok", "rating", min=10)], "field_defs.0.min", "value_error"),
        ([field_def("ok", "rating", max=0)], "field_defs.0.max", "value_error"),
        ([field_def("a"), field_def("b"), field_def("a")], "field_defs.2.key", "value_error"),
        ([field_def(f"f{i}") for i in range(13)], "field_defs", "too_long"),
    ],
)
def test_field_def_shape_errors(
    client: TestClient,
    owner: Account,
    group: dict[str, Any],
    field_defs: list[dict[str, Any]],
    field: str,
    error_type: str,
) -> None:
    response = post_category(
        client, owner, group["id"], name="X", color="#000000", field_defs=field_defs
    )

    assert response.status_code == 422, response.text
    assert response.json()["code"] == "validation_error"
    assert (field, error_type) in [(e["field"], e["type"]) for e in response.json()["errors"]]


def test_valid_field_defs_are_normalized(
    client: TestClient, owner: Account, group: dict[str, Any]
) -> None:
    category = create_category(
        client,
        owner,
        group["id"],
        field_defs=[
            {"key": " vibe ", "label": " Vibe ", "type": "select", "options": [" Chill ", "Wild"]},
            field_def("score", "rating", max=5, show_on_card=True),
            field_def("price", "number", min=-1.5),
            field_def("year", "year"),
            field_def("f" + "x" * 29, "long_text"),
        ]
        + [field_def(f"extra{i}") for i in range(7)],
    )

    first, second = category["field_defs"][:2]
    assert first == {
        "key": "vibe",
        "label": "Vibe",
        "type": "select",
        "options": ["Chill", "Wild"],
        "min": None,
        "max": None,
        "show_on_card": False,
    }
    assert (second["min"], second["max"], second["show_on_card"]) == (None, 5, True)
    assert len(category["field_defs"]) == 12


def test_field_key_conflicts_in_all_three_directions(
    client: TestClient, owner: Account, group: dict[str, Any]
) -> None:
    parent = create_category(client, owner, group["id"], field_defs=[field_def("genre")])
    child = create_category(
        client, owner, group["id"], parent_id=parent["id"], field_defs=[field_def("director")]
    )
    other = create_category(client, owner, group["id"], field_defs=[field_def("director")])

    # 1. a subcategory reuses a key of its parent
    sub_save = post_category(
        client,
        owner,
        group["id"],
        name="Y",
        parent_id=parent["id"],
        field_defs=[field_def("genre")],
    )
    # 2. a parent gets a key one of its subcategories has
    parent_save = put_category(
        client, owner, parent, field_defs=[field_def("genre"), field_def("director")]
    )
    # 3. a subcategory moves under a parent with the same key
    move = put_category(client, owner, child, parent_id=other["id"])

    for response, field in [
        (sub_save, "field_defs.0.key"),
        (parent_save, "field_defs.1.key"),
        (move, "field_defs.0.key"),
    ]:
        assert response.status_code == 422, response.text
        assert response.json()["code"] == "field_key_conflict"
        assert response.json()["errors"][0]["field"] == field
    # Siblings may share keys.
    sibling = post_category(
        client,
        owner,
        group["id"],
        name="Sibling",
        parent_id=parent["id"],
        field_defs=[field_def("director")],
    )
    assert sibling.status_code == 201


def test_a_field_type_cannot_change_in_one_put(
    client: TestClient, owner: Account, group: dict[str, Any]
) -> None:
    category = create_category(
        client, owner, group["id"], field_defs=[field_def("a"), field_def("year", "number")]
    )

    changed = put_category(
        client, owner, category, field_defs=[field_def("a"), field_def("year", "year")]
    )
    removed = put_category(client, owner, category, field_defs=[field_def("a")])
    re_added = put_category(
        client, owner, category, field_defs=[field_def("year", "year"), field_def("a", label="A2")]
    )

    assert changed.status_code == 422
    assert changed.json()["code"] == "field_type_change"
    assert changed.json()["errors"][0]["field"] == "field_defs.1.type"
    assert removed.status_code == 200
    assert re_added.status_code == 200
    assert [(f["key"], f["type"]) for f in re_added.json()["field_defs"]] == [
        ("year", "year"),
        ("a", "text"),
    ]


# --- permissions --------------------------------------------------------------------------


def test_members_create_and_manage_only_their_own_categories(
    client: TestClient, owner: Account, group: dict[str, Any]
) -> None:
    member = add_member(client, owner, group["id"])
    admin = add_member(client, owner, group["id"])
    client.put(
        f"/api/v1/groups/{group['id']}/members/{admin.id}/role",
        headers=owner.headers,
        json={"role": "admin"},
    )
    mine = create_category(client, member, group["id"], name="Mine")
    theirs = create_category(client, owner, group["id"], name="Theirs")

    listed = {c["name"]: c for c in list_categories(client, member, group["id"])}
    assert (listed["Mine"]["can_edit"], listed["Mine"]["can_delete"]) == (True, True)
    assert (listed["Theirs"]["can_edit"], listed["Theirs"]["can_delete"]) == (False, False)
    assert put_category(client, member, theirs, name="Hijacked").status_code == 403
    assert (
        client.delete(f"/api/v1/categories/{theirs['id']}", headers=member.headers).status_code
        == 403
    )
    assert put_category(client, member, mine, name="Still mine").status_code == 200
    assert put_category(client, admin, mine, name="Admin edit").json()["can_edit"] is True
    assert (
        client.delete(f"/api/v1/categories/{mine['id']}", headers=admin.headers).status_code == 204
    )


# --- deletion -----------------------------------------------------------------------------


def _get(client: TestClient, account: Account, activity: dict[str, Any]) -> dict[str, Any]:
    body: dict[str, Any] = client.get(
        f"/api/v1/activities/{activity['id']}", headers=account.headers
    ).json()
    return body


def test_deleting_a_subcategory_moves_its_activities_to_the_parent(
    client: TestClient, owner: Account, group: dict[str, Any]
) -> None:
    parent = create_category(client, owner, group["id"])
    child = create_category(client, owner, group["id"], parent_id=parent["id"])
    moved = create_activity(client, owner, group["id"], category_id=child["id"])
    untouched = create_activity(client, owner, group["id"], category_id=parent["id"])

    response = client.delete(f"/api/v1/categories/{child['id']}", headers=owner.headers)

    assert response.status_code == 204
    after = _get(client, owner, moved)
    assert after["category_id"] == parent["id"]
    assert after["version"] == moved["version"] + 1
    assert _get(client, owner, untouched)["version"] == untouched["version"]
    assert [c["subcategories"] for c in list_categories(client, owner, group["id"])] == [[]]


def test_deleting_a_top_level_category_uncategorizes_everything_in_it(
    client: TestClient, owner: Account, group: dict[str, Any]
) -> None:
    parent = create_category(client, owner, group["id"])
    child = create_category(client, owner, group["id"], parent_id=parent["id"])
    other = create_category(client, owner, group["id"])
    in_parent = create_activity(client, owner, group["id"], category_id=parent["id"])
    in_child = create_activity(client, owner, group["id"], category_id=child["id"])
    elsewhere = create_activity(client, owner, group["id"], category_id=other["id"])

    response = client.delete(f"/api/v1/categories/{parent['id']}", headers=owner.headers)

    assert response.status_code == 204
    for activity in (in_parent, in_child):
        after = _get(client, owner, activity)
        assert after["category_id"] is None
        assert after["version"] == activity["version"] + 1
    assert _get(client, owner, elsewhere)["category_id"] == other["id"]
    assert [c["id"] for c in list_categories(client, owner, group["id"])] == [other["id"]]
    assert (
        client.put(
            f"/api/v1/categories/{child['id']}", headers=owner.headers, json={"name": "x"}
        ).status_code
        == 404
    )


def test_category_changes_are_logged(
    client: TestClient, owner: Account, group: dict[str, Any], db_session: Session
) -> None:
    category = create_category(client, owner, group["id"], name="Logged")
    put_category(client, owner, category)  # no change: not logged
    put_category(client, owner, category, name="Renamed")
    client.delete(f"/api/v1/categories/{category['id']}", headers=owner.headers)

    rows = db_session.execute(
        select(GroupLog.action, GroupLog.data)
        .where(GroupLog.subject_type == "category")
        .order_by(GroupLog.id)
    ).all()

    assert [tuple(row) for row in rows] == [
        ("category.created", {"name": "Logged"}),
        ("category.updated", {"name": "Renamed"}),
        ("category.deleted", {"name": "Renamed"}),
    ]


def test_deleting_a_top_level_category_logs_each_deleted_subcategory(
    client: TestClient, owner: Account, group: dict[str, Any], db_session: Session
) -> None:
    parent = create_category(client, owner, group["id"], name="Parent")
    second = create_category(
        client, owner, group["id"], parent_id=parent["id"], name="Second", position=1
    )
    first = create_category(
        client, owner, group["id"], parent_id=parent["id"], name="First", position=0
    )
    create_category(client, owner, group["id"], name="Kept")

    response = client.delete(f"/api/v1/categories/{parent['id']}", headers=owner.headers)

    assert response.status_code == 204
    rows = db_session.execute(
        select(GroupLog.actor_id, GroupLog.subject_id, GroupLog.data)
        .where(GroupLog.action == "category.deleted")
        .order_by(GroupLog.id)
    ).all()
    assert [(str(actor), str(subject), data) for actor, subject, data in rows] == [
        (owner.id, parent["id"], {"name": "Parent"}),
        (owner.id, first["id"], {"name": "First"}),
        (owner.id, second["id"], {"name": "Second"}),
    ]


# --- reordering (issue #18) ---------------------------------------------------------------


def reorder(client: TestClient, account: Account, group_id: str, **body: Any) -> Any:
    return client.put(
        f"/api/v1/groups/{group_id}/categories/order", headers=account.headers, json=body
    )


def test_admins_reorder_top_level_categories(client: TestClient, db_session: Session) -> None:
    owner = register(client)
    gid = create_group(client, owner)["id"]
    ids = [c["id"] for c in list_categories(client, owner, gid)]
    new_order = [*reversed(ids)]

    response = reorder(client, owner, gid, category_ids=new_order)

    assert response.status_code == 200, response.text
    assert [c["id"] for c in response.json()] == new_order
    assert [c["position"] for c in response.json()] == list(range(len(ids)))
    assert [c["id"] for c in list_categories(client, owner, gid)] == new_order
    logged = db_session.scalars(
        select(GroupLog).where(GroupLog.action == "category.reordered")
    ).one()
    assert logged.subject_id is None
    assert logged.data == {"count": len(ids)}


def test_subcategories_are_reordered_under_their_parent(client: TestClient) -> None:
    owner = register(client)
    gid = create_group(client, owner)["id"]
    parent = list_categories(client, owner, gid)[0]
    subs = [
        create_category(client, owner, gid, name=name, parent_id=parent["id"])["id"]
        for name in ("A", "B", "C")
    ]

    response = reorder(
        client, owner, gid, parent_id=parent["id"], category_ids=[subs[2], subs[0], subs[1]]
    )

    assert response.status_code == 200, response.text
    node = next(c for c in response.json() if c["id"] == parent["id"])
    assert [s["name"] for s in node["subcategories"]] == ["C", "A", "B"]


@pytest.mark.parametrize("change", ["missing", "extra", "repeated", "subcategory"])
def test_the_order_must_list_every_sibling_once(client: TestClient, change: str) -> None:
    owner = register(client)
    gid = create_group(client, owner)["id"]
    ids = [c["id"] for c in list_categories(client, owner, gid)]
    sub = create_category(client, owner, gid, name="Sub", parent_id=ids[0])["id"]
    order = {
        "missing": ids[1:],
        "extra": [*ids, str(uuid.uuid4())],
        "repeated": [*ids[:-1], ids[0]],
        "subcategory": [*ids, sub],
    }[change]

    response = reorder(client, owner, gid, category_ids=order)

    assert response.status_code == 422
    assert response.json()["errors"][0]["field"] == "category_ids"


def test_reordering_under_a_subcategory_or_another_group_is_rejected(
    client: TestClient,
) -> None:
    owner = register(client)
    gid = create_group(client, owner)["id"]
    other = create_group(client, owner)["id"]
    top = list_categories(client, owner, gid)[0]["id"]
    sub = create_category(client, owner, gid, name="Sub", parent_id=top)["id"]
    foreign = list_categories(client, owner, other)[0]["id"]

    assert reorder(client, owner, gid, parent_id=foreign, category_ids=[]).status_code == 422
    response = reorder(client, owner, gid, parent_id=sub, category_ids=[])
    assert response.status_code == 422
    assert response.json()["code"] == "category_depth_exceeded"


def test_members_cannot_reorder(client: TestClient) -> None:
    owner = register(client)
    gid = create_group(client, owner)["id"]
    member = add_member(client, owner, gid)
    ids = [c["id"] for c in list_categories(client, owner, gid)]

    response = reorder(client, member, gid, category_ids=ids)

    assert response.status_code == 403
