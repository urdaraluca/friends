"""Availability (contract section 13): my answers and the group heatmap."""

from datetime import date, timedelta
from typing import Any

import pytest
from fastapi.testclient import TestClient

from friends_api.features.availability.models import AvailabilitySlot as Slot
from friends_api.features.availability.models import AvailabilityStatus as Status
from friends_api.features.availability.service import day_status, slot_status
from tests.factories import Account, add_member, create_group, register

FREE, MAYBE, BUSY = Status.FREE, Status.MAYBE, Status.BUSY


def put_mine(
    client: TestClient,
    account: Account,
    entries: list[tuple[str, str, str]],
    *,
    from_date: str = "2026-10-01",
    to_date: str = "2026-10-15",
) -> Any:
    return client.put(
        "/api/v1/me/availability",
        headers=account.headers,
        json={
            "from_date": from_date,
            "to_date": to_date,
            "entries": [{"date": d, "slot": s, "status": st} for d, s, st in entries],
        },
    )


def heatmap(client: TestClient, account: Account, group_id: str, **params: str) -> dict[str, Any]:
    response = client.get(
        f"/api/v1/groups/{group_id}/availability",
        headers=account.headers,
        params={"from": "2026-10-01", "to": "2026-10-15", **params},
    )
    assert response.status_code == 200, response.text
    body: dict[str, Any] = response.json()
    return body


def day(body: dict[str, Any], value: str) -> dict[str, Any]:
    found: dict[str, Any] = next(d for d in body["days"] if d["date"] == value)
    return found


def slot(body: dict[str, Any], value: str, name: str) -> dict[str, Any]:
    found: dict[str, Any] = next(s for s in day(body, value)["slots"] if s["slot"] == name)
    return found


# --- the rules ----------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("answers", "whole"),
    [
        ({}, None),
        ({Slot.ALL_DAY: BUSY, Slot.MORNING: FREE}, BUSY),  # the whole-day answer wins
        ({Slot.MORNING: FREE, Slot.AFTERNOON: FREE, Slot.EVENING: FREE}, FREE),
        ({Slot.MORNING: BUSY, Slot.EVENING: FREE}, MAYBE),
        ({Slot.MORNING: MAYBE}, MAYBE),
        ({Slot.MORNING: BUSY, Slot.AFTERNOON: BUSY, Slot.EVENING: BUSY}, BUSY),
        ({Slot.MORNING: BUSY}, None),  # busy in the morning says nothing about the rest
    ],
)
def test_day_status(answers: dict[Slot, Status], whole: Status | None) -> None:
    assert day_status(answers) is whole


def test_a_part_of_the_day_falls_back_to_the_whole_day() -> None:
    answers = {Slot.ALL_DAY: MAYBE, Slot.EVENING: FREE}

    assert slot_status(answers, Slot.EVENING) is FREE
    assert slot_status(answers, Slot.MORNING) is MAYBE
    assert slot_status({}, Slot.MORNING) is None


# --- my availability ----------------------------------------------------------------------


def test_put_replaces_my_answers_in_the_range(client: TestClient) -> None:
    ana = register(client)
    first = put_mine(
        client,
        ana,
        [("2026-10-02", "evening", "free"), ("2026-10-01", "all_day", "busy")],
    )
    outside = put_mine(
        client,
        ana,
        [("2026-11-01", "all_day", "free")],
        from_date="2026-11-01",
        to_date="2026-11-02",
    )
    second = put_mine(client, ana, [("2026-10-03", "morning", "maybe")])

    assert first.status_code == 200, first.text
    assert first.json()["entries"] == [
        {"date": "2026-10-01", "slot": "all_day", "status": "busy"},
        {"date": "2026-10-02", "slot": "evening", "status": "free"},
    ]
    assert outside.status_code == 200
    assert second.json()["entries"] == [
        {"date": "2026-10-03", "slot": "morning", "status": "maybe"}
    ]
    mine = client.get(
        "/api/v1/me/availability",
        headers=ana.headers,
        params={"from": "2026-10-01", "to": "2026-11-05"},
    )
    assert mine.status_code == 200
    assert [(e["date"], e["slot"]) for e in mine.json()["entries"]] == [
        ("2026-10-03", "morning"),
        ("2026-11-01", "all_day"),  # outside the second PUT's range: kept
    ]


def test_put_validation(client: TestClient) -> None:
    ana = register(client)

    outside = put_mine(client, ana, [("2026-10-20", "all_day", "free")])
    duplicate = put_mine(
        client,
        ana,
        [("2026-10-02", "evening", "free"), ("2026-10-02", "evening", "busy")],
    )
    backwards = put_mine(client, ana, [], from_date="2026-10-15", to_date="2026-10-01")
    too_long = put_mine(client, ana, [], from_date="2026-01-01", to_date="2026-06-01")
    bad_slot = put_mine(client, ana, [("2026-10-02", "night", "free")])

    assert outside.status_code == 422
    assert [e["field"] for e in outside.json()["errors"]] == ["entries.0.date"]
    assert duplicate.status_code == 422
    assert [e["field"] for e in duplicate.json()["errors"]] == ["entries.1"]
    assert backwards.status_code == 422
    assert backwards.json()["code"] == "validation_error"
    assert too_long.status_code == 422
    assert too_long.json()["code"] == "range_too_large"
    assert bad_slot.status_code == 422


def test_get_range_limits(client: TestClient) -> None:
    ana = register(client)

    ok = client.get(
        "/api/v1/me/availability",
        headers=ana.headers,
        params={"from": "2026-01-01", "to": str(date(2026, 1, 1) + timedelta(days=92))},
    )
    too_long = client.get(
        "/api/v1/me/availability",
        headers=ana.headers,
        params={"from": "2026-01-01", "to": str(date(2026, 1, 1) + timedelta(days=93))},
    )

    assert ok.status_code == 200
    assert too_long.json()["code"] == "range_too_large"


# --- the group heatmap --------------------------------------------------------------------


def test_heatmap_counts_names_and_best_days(client: TestClient) -> None:
    owner = register(client, display_name="Ana")
    group = create_group(client, owner)
    bea = add_member(client, owner, group["id"])
    cris = add_member(client, owner, group["id"])
    stranger = register(client)
    put_mine(client, owner, [("2026-10-03", "all_day", "free"), ("2026-10-04", "all_day", "free")])
    put_mine(client, bea, [("2026-10-03", "all_day", "maybe"), ("2026-10-04", "all_day", "free")])
    put_mine(client, cris, [("2026-10-03", "all_day", "free"), ("2026-10-04", "evening", "busy")])
    put_mine(client, stranger, [("2026-10-05", "all_day", "free")])  # not in the group

    body = heatmap(client, owner, group["id"])

    assert body["member_count"] == 3
    assert len(body["days"]) == 14
    saturday = slot(body, "2026-10-03", "all_day")
    assert (saturday["free"], saturday["maybe"], saturday["busy"], saturday["unknown"]) == (
        2,
        1,
        0,
        0,
    )
    assert {u["display_name"] for u in saturday["free_users"]} >= {"Ana"}
    assert "busy_users" not in saturday  # busy is a count only
    # Sunday: two free all day; Cris is busy in the evening only, unknown for the day.
    assert (
        slot(body, "2026-10-04", "all_day")["free"],
        slot(body, "2026-10-04", "all_day")["unknown"],
    ) == (2, 1)
    assert slot(body, "2026-10-04", "evening")["busy"] == 1
    assert slot(body, "2026-10-04", "morning")["free"] == 2
    # Best days: Saturday scores 2.5, Sunday 2; nobody from outside the group counts.
    assert [(b["date"], b["score"]) for b in body["best_days"]] == [
        ("2026-10-03", 2.5),
        ("2026-10-04", 2.0),
    ]
    assert day(body, "2026-10-05")["score"] == 0


def test_ties_break_on_fewer_busy_then_the_earliest(client: TestClient) -> None:
    owner = register(client)
    group = create_group(client, owner)
    bea = add_member(client, owner, group["id"])
    put_mine(client, owner, [(f"2026-10-0{d}", "all_day", "free") for d in (2, 3, 4)])
    put_mine(client, bea, [("2026-10-02", "all_day", "busy"), ("2026-10-04", "all_day", "busy")])

    body = heatmap(client, owner, group["id"])

    assert [b["date"] for b in body["best_days"]] == ["2026-10-03", "2026-10-02", "2026-10-04"]


def test_former_members_no_longer_count(client: TestClient) -> None:
    owner = register(client)
    group = create_group(client, owner)
    bea = add_member(client, owner, group["id"])
    put_mine(client, bea, [("2026-10-03", "all_day", "free")])
    left = client.delete(f"/api/v1/groups/{group['id']}/members/{bea.id}", headers=bea.headers)
    assert left.status_code == 204

    body = heatmap(client, owner, group["id"])

    assert body["member_count"] == 1
    assert body["best_days"] == []


def test_heatmap_range_and_membership(client: TestClient) -> None:
    owner = register(client)
    group = create_group(client, owner)
    outsider = register(client)

    too_long = client.get(
        f"/api/v1/groups/{group['id']}/availability",
        headers=owner.headers,
        params={"from": "2026-01-01", "to": "2026-06-01"},
    )
    hidden = client.get(
        f"/api/v1/groups/{group['id']}/availability",
        headers=outsider.headers,
        params={"from": "2026-10-01", "to": "2026-10-15"},
    )

    assert too_long.json()["code"] == "range_too_large"
    assert hidden.status_code == 404
