"""Contract section 7.4: every route with a UUID path parameter is checked automatically.

1. An authenticated non-member always gets 404 (same as a missing resource).
2. Routes restricted to admins / owners / creators give a plain member 403.

A new route must be classified below, or ``test_every_uuid_route_is_classified`` fails.
"""

import re
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any

import pytest
from fastapi import FastAPI
from fastapi.routing import APIRoute, RouteContext, iter_route_contexts
from fastapi.testclient import TestClient

from tests.factories import (
    Account,
    add_member,
    create_activity,
    create_event,
    create_group,
    create_invite,
    create_poll,
    list_categories,
    register,
)


@dataclass
class World:
    owner: Account
    member: Account
    outsider: Account
    ids: dict[str, str]


GROUP_UPDATE = {"name": "G", "currency": "EUR", "timezone": "UTC", "members_can_invite": True}
CATEGORY_WRITE = {"name": "Board games", "color": "#123456"}
POLL_UPDATE = {"question": "Which one?", "closes_at": None}
EVENT_WRITE = {"kind": "one_time", "title": "Picnic", "all_day": True, "start_date": "2026-10-03"}

# operationId -> request body. A plain member (not creator/owner) must get 403.
RESTRICTED: dict[str, Callable[[World], dict[str, Any] | None]] = {
    "update_group": lambda w: GROUP_UPDATE,
    "delete_group": lambda w: None,
    "transfer_ownership": lambda w: {"user_id": w.ids["other_member_id"]},
    "update_member_role": lambda w: {"role": "admin"},
    "remove_member": lambda w: None,
    "revoke_invite": lambda w: None,
    "update_category": lambda w: CATEGORY_WRITE,
    "delete_category": lambda w: None,
    "delete_activity": lambda w: None,
    "update_poll": lambda w: POLL_UPDATE,
    "delete_poll": lambda w: None,
    "close_poll": lambda w: None,
    "reopen_poll": lambda w: None,
    # A plain member who neither added the option nor manages the poll.
    "delete_poll_option": lambda w: None,
    "update_event": lambda w: {**EVENT_WRITE, "version": 1},
    "delete_event": lambda w: None,
    "cancel_occurrence": lambda w: None,
    "restore_occurrence": lambda w: None,
}

# Routes any member may use (non-members still get 404).
MEMBER_LEVEL = {
    "get_group",
    "list_members",
    "update_my_member_settings",
    "list_invites",
    "create_invite",
    "list_categories",
    "create_category",
    "list_activities",
    "create_activity",
    "get_activity",
    "update_activity",
    "set_activity_status",
    "add_interest",
    "remove_interest",
    "list_wheel_candidates",
    "create_spin",
    "list_spins",
    "accept_spin",
    "list_polls",
    "create_poll",
    "get_poll",
    "add_poll_option",
    "set_my_vote",
    "get_group_calendar",
    "get_group_availability",
    "get_group_recap",
    "list_group_feed",
    "create_event",
    "get_event",
}

BODIES: dict[str, Callable[[World], dict[str, Any] | None]] = {
    **RESTRICTED,
    "update_my_member_settings": lambda w: {"show_birthday": False},
    "create_invite": lambda w: {},
    "create_category": lambda w: CATEGORY_WRITE,
    "create_activity": lambda w: {"title": "Picnic"},
    "update_activity": lambda w: {"title": "Picnic", "version": 1},
    "set_activity_status": lambda w: {"status": "planning"},
    "create_spin": lambda w: {"filters": {}},
    "create_poll": lambda w: {"question": "When?", "options": [{"label": "A"}, {"label": "B"}]},
    "add_poll_option": lambda w: {"label": "Another one"},
    "set_my_vote": lambda w: {"option_ids": [w.ids["option_id"]]},
    "create_event": lambda w: EVENT_WRITE,
}

# operationId -> query parameters the route requires.
QUERIES: dict[str, dict[str, str]] = {
    "get_group_calendar": {"from": "2026-10-01", "to": "2026-11-01"},
    "get_group_availability": {"from": "2026-10-01", "to": "2026-10-15"},
    "get_group_recap": {"period": "month"},
}


@pytest.fixture
def world(client: TestClient) -> World:
    owner = register(client)
    group = create_group(client, owner)
    member = add_member(client, owner, group["id"])
    other = add_member(client, owner, group["id"])
    invite = create_invite(client, owner, group["id"])
    # Created by the owner: the plain member is neither its creator nor its owner.
    category = list_categories(client, owner, group["id"])[0]
    activity = create_activity(client, owner, group["id"], title="Owned by the owner")
    # Spun by the owner over two activities (#8).
    spin = client.post(
        f"/api/v1/groups/{group['id']}/wheel/spins",
        headers=owner.headers,
        json={
            "filters": {},
            "activity_ids": [activity["id"], create_activity(client, owner, group["id"])["id"]],
        },
    ).json()
    # Created by the owner on the owner's activity: the plain member doesn't manage it, and
    # its options were added by the owner.
    poll = create_poll(client, owner, activity["id"])
    event = create_event(
        client,
        owner,
        group["id"],
        kind="recurring",
        all_day=False,
        starts_at="2026-10-01T16:00:00Z",
        ends_at="2026-10-01T19:00:00Z",
        rrule="FREQ=WEEKLY;BYDAY=TH",
    )
    return World(
        owner=owner,
        member=member,
        outsider=register(client),
        ids={
            "group_id": group["id"],
            # The target of member-targeted routes is another plain member.
            "user_id": other.id,
            "other_member_id": other.id,
            "invite_id": invite["id"],
            "category_id": category["id"],
            "activity_id": activity["id"],
            "spin_id": spin["id"],
            "poll_id": poll["id"],
            "option_id": poll["options"][0]["id"],
            "event_id": event["id"],
            # Not a UUID: the cancel and restore routes also take a (valid) occurrence key.
            "occurrence_key": "20261008T160000Z",
        },
    )


def uuid_routes(app: FastAPI) -> list[tuple[RouteContext, str]]:
    # FastAPI >= 0.141 keeps included routers as nodes; iter_route_contexts flattens them.
    routes: list[tuple[RouteContext, str]] = []
    for route in iter_route_contexts(app.routes):
        if isinstance(route.original_route, APIRoute) and re.search(
            r"\{\w+_id\}", route.path or ""
        ):
            routes.extend((route, method) for method in sorted(route.methods or ()))
    return routes


def call(
    client: TestClient, route: RouteContext, method: str, world: World, account: Account
) -> Any:
    path = (route.path or "").format(**world.ids)
    body_factory = BODIES.get(route.name or "")
    body = body_factory(world) if body_factory else None
    params = QUERIES.get(route.name or "")
    return client.request(method, path, headers=account.headers, json=body, params=params)


def test_every_uuid_route_is_classified(app: FastAPI) -> None:
    names = {route.name for route, _ in uuid_routes(app)}

    assert names, "no routes found"
    assert names <= set(RESTRICTED) | MEMBER_LEVEL, names - set(RESTRICTED) - MEMBER_LEVEL


def test_non_members_get_404_everywhere(app: FastAPI, client: TestClient, world: World) -> None:
    for route, method in uuid_routes(app):
        response = call(client, route, method, world, world.outsider)
        assert response.status_code == 404, (method, route.path, response.text)
        assert response.json()["code"] == "not_found"


def test_plain_members_get_403_on_restricted_routes(
    app: FastAPI, client: TestClient, world: World
) -> None:
    for route, method in uuid_routes(app):
        if route.name not in RESTRICTED:
            continue
        response = call(client, route, method, world, world.member)
        assert response.status_code == 403, (method, route.path, response.text)
        assert response.json()["code"] == "forbidden"


def test_member_level_routes_accept_a_plain_member(
    app: FastAPI, client: TestClient, world: World
) -> None:
    """The bodies above are valid, so the 403s in the previous test come from the rules."""
    for route, method in uuid_routes(app):
        if route.name not in MEMBER_LEVEL or method != "GET":
            continue
        response = call(client, route, method, world, world.member)
        assert response.status_code == 200, (method, route.path, response.text)
