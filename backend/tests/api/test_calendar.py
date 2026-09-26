"""Calendar queries (contract sections 5.5 and 5.7): ``GET /groups/{id}/calendar`` and
``GET /me/calendar``."""

from datetime import date, timedelta
from typing import Any

import pytest
from fastapi.testclient import TestClient

from tests.factories import (
    Account,
    add_member,
    create_category,
    create_event,
    create_group,
    list_categories,
    register,
)

WEEKLY_THURSDAY_1900_BUCHAREST = {
    "kind": "recurring",
    "all_day": False,
    "starts_at": "2026-10-01T16:00:00Z",
    "ends_at": "2026-10-01T19:00:00Z",
    "timezone": "Europe/Bucharest",
    "rrule": "FREQ=WEEKLY;BYDAY=TH",
}


def group_calendar(
    client: TestClient, account: Account, group_id: str, **params: Any
) -> dict[str, Any]:
    response = client.get(
        f"/api/v1/groups/{group_id}/calendar", headers=account.headers, params=params
    )
    assert response.status_code == 200, response.text
    body: dict[str, Any] = response.json()
    return body


def my_calendar(client: TestClient, account: Account, **params: Any) -> dict[str, Any]:
    response = client.get("/api/v1/me/calendar", headers=account.headers, params=params)
    assert response.status_code == 200, response.text
    body: dict[str, Any] = response.json()
    return body


def set_birthday(
    client: TestClient, account: Account, month: int, day: int, year: int | None = None
) -> None:
    me = client.get("/api/v1/me", headers=account.headers).json()
    response = client.put(
        "/api/v1/me",
        headers=account.headers,
        json={
            "display_name": me["display_name"],
            "birthday": {"month": month, "day": day, "year": year},
            "timezone": me["timezone"],
            "locale": None,
            "avatar_url": None,
        },
    )
    assert response.status_code == 200, response.text


def show_birthday(client: TestClient, account: Account, group_id: str, *, show: bool) -> None:
    response = client.put(
        f"/api/v1/groups/{group_id}/members/me/settings",
        headers=account.headers,
        json={"show_birthday": show},
    )
    assert response.status_code == 200, response.text


def titles(body: dict[str, Any]) -> list[str]:
    return [o["title"] for o in body["occurrences"]]


@pytest.fixture
def owner(client: TestClient) -> Account:
    return register(client, display_name="Olga", timezone="Europe/Bucharest")


@pytest.fixture
def group(client: TestClient, owner: Account) -> dict[str, Any]:
    return create_group(client, owner, timezone="Europe/Bucharest")


# --- timed recurrence across DST ------------------------------------------------------------


def test_a_weekly_thursday_stays_at_1900_local_across_the_dst_change(
    client: TestClient, owner: Account, group: dict[str, Any]
) -> None:
    event = create_event(
        client, owner, group["id"], title="Game night", **WEEKLY_THURSDAY_1900_BUCHAREST
    )

    body = group_calendar(
        client,
        owner,
        group["id"],
        **{"from": "2026-10-01", "to": "2026-11-01"},
        tz="Europe/Bucharest",
    )

    assert body["from_date"] == "2026-10-01"
    assert body["to_date"] == "2026-11-01"
    assert body["tz"] == "Europe/Bucharest"
    starts = [(o["starts_at"], o["ends_at"]) for o in body["occurrences"]]
    assert starts == [
        ("2026-10-01T16:00:00Z", "2026-10-01T19:00:00Z"),
        ("2026-10-08T16:00:00Z", "2026-10-08T19:00:00Z"),
        ("2026-10-15T16:00:00Z", "2026-10-15T19:00:00Z"),
        ("2026-10-22T16:00:00Z", "2026-10-22T19:00:00Z"),
        ("2026-10-29T17:00:00Z", "2026-10-29T20:00:00Z"),  # 19:00 local after the change
    ]
    first = body["occurrences"][0]
    assert first == {
        "occurrence_key": "20261001T160000Z",
        "source": "event",
        "event_id": event["id"],
        "user_id": None,
        "group_id": group["id"],
        "kind": "recurring",
        "title": "Game night",
        "all_day": False,
        "starts_at": "2026-10-01T16:00:00Z",
        "ends_at": "2026-10-01T19:00:00Z",
        "start_date": None,
        "end_date": None,
        "timezone": "Europe/Bucharest",
        "category_id": None,
        "color": None,
        "activity_id": None,
        "is_recurring": True,
        "can_edit": True,
    }


def test_a_timed_occurrence_is_included_when_it_overlaps_the_range(
    client: TestClient, owner: Account, group: dict[str, Any]
) -> None:
    # 22:00-02:00 Bucharest time, crossing into 2 October.
    create_event(
        client,
        owner,
        group["id"],
        title="Late",
        all_day=False,
        starts_at="2026-10-01T19:00:00Z",
        ends_at="2026-10-01T23:00:00Z",
    )

    on_the_second = group_calendar(
        client,
        owner,
        group["id"],
        **{"from": "2026-10-02", "to": "2026-10-03"},
        tz="Europe/Bucharest",
    )
    on_the_third = group_calendar(
        client,
        owner,
        group["id"],
        **{"from": "2026-10-03", "to": "2026-10-04"},
        tz="Europe/Bucharest",
    )

    assert titles(on_the_second) == ["Late"]
    assert titles(on_the_third) == []


def test_cancelled_occurrences_are_left_out(
    client: TestClient, owner: Account, group: dict[str, Any]
) -> None:
    event = create_event(client, owner, group["id"], **WEEKLY_THURSDAY_1900_BUCHAREST)
    cancel = client.delete(
        f"/api/v1/events/{event['id']}/occurrences/20261008T160000Z", headers=owner.headers
    )
    assert cancel.status_code == 204

    body = group_calendar(client, owner, group["id"], **{"from": "2026-10-01", "to": "2026-10-16"})

    assert [o["occurrence_key"] for o in body["occurrences"]] == [
        "20261001T160000Z",
        "20261015T160000Z",
    ]


# --- floating dates -------------------------------------------------------------------------


@pytest.mark.parametrize("tz", ["Pacific/Honolulu", "Pacific/Kiritimati", "UTC"])
def test_a_three_day_all_day_event_covers_the_same_three_dates_in_every_zone(
    client: TestClient, owner: Account, group: dict[str, Any], tz: str
) -> None:
    create_event(
        client,
        owner,
        group["id"],
        title="Trip",
        all_day=True,
        start_date="2026-10-09",
        end_date="2026-10-11",
    )

    shown_on = []
    for offset in range(-1, 4):
        day = date(2026, 10, 9) + timedelta(days=offset)
        body = group_calendar(
            client,
            owner,
            group["id"],
            **{"from": day.isoformat(), "to": (day + timedelta(days=1)).isoformat()},
            tz=tz,
        )
        if body["occurrences"]:
            shown_on.append(day.isoformat())
            (occurrence,) = body["occurrences"]
            assert (occurrence["start_date"], occurrence["end_date"]) == (
                "2026-10-09",
                "2026-10-11",
            )
            assert occurrence["starts_at"] is None
            assert occurrence["occurrence_key"] == "20261009"

    assert shown_on == ["2026-10-09", "2026-10-10", "2026-10-11"]


# --- validation -----------------------------------------------------------------------------


def test_to_must_be_after_from(client: TestClient, owner: Account, group: dict[str, Any]) -> None:
    for to in ("2026-10-01", "2026-09-30"):
        response = client.get(
            f"/api/v1/groups/{group['id']}/calendar",
            headers=owner.headers,
            params={"from": "2026-10-01", "to": to},
        )

        assert response.status_code == 422
        assert response.json()["code"] == "validation_error"
        assert [e["field"] for e in response.json()["errors"]] == ["query.to"]


def test_the_range_is_at_most_400_days(
    client: TestClient, owner: Account, group: dict[str, Any]
) -> None:
    ok = client.get(
        f"/api/v1/groups/{group['id']}/calendar",
        headers=owner.headers,
        params={"from": "2026-01-01", "to": str(date(2026, 1, 1) + timedelta(days=400))},
    )
    too_large = client.get(
        f"/api/v1/groups/{group['id']}/calendar",
        headers=owner.headers,
        params={"from": "2026-01-01", "to": str(date(2026, 1, 1) + timedelta(days=401))},
    )
    mine = client.get(
        "/api/v1/me/calendar",
        headers=owner.headers,
        params={"from": "2026-01-01", "to": "2027-12-31"},
    )

    assert ok.status_code == 200
    assert too_large.status_code == 422
    assert too_large.json()["code"] == "range_too_large"
    assert mine.status_code == 422
    assert mine.json()["code"] == "range_too_large"


@pytest.mark.parametrize(
    "params",
    [
        {"from": "2026-10-01"},
        {"to": "2026-10-01"},
        {"from": "2026-10-01T10:00:00Z", "to": "2026-10-02"},
    ],
)
def test_from_and_to_are_required_dates(
    client: TestClient, owner: Account, group: dict[str, Any], params: dict[str, str]
) -> None:
    response = client.get(
        f"/api/v1/groups/{group['id']}/calendar", headers=owner.headers, params=params
    )

    assert response.status_code == 422
    assert response.json()["code"] == "validation_error"


def test_an_invalid_tz_falls_back_to_the_callers_timezone(
    client: TestClient, owner: Account, group: dict[str, Any]
) -> None:
    body = group_calendar(
        client, owner, group["id"], **{"from": "2026-10-01", "to": "2026-10-02"}, tz="Mars/Olympus"
    )
    default = group_calendar(
        client, owner, group["id"], **{"from": "2026-10-01", "to": "2026-10-02"}
    )

    assert body["tz"] == "Europe/Bucharest"
    assert default["tz"] == "Europe/Bucharest"


def test_the_range_follows_tz(client: TestClient, owner: Account, group: dict[str, Any]) -> None:
    # 23:30-23:45 UTC on 1 October is already 2 October in Bucharest.
    create_event(
        client,
        owner,
        group["id"],
        title="Midnight snack",
        all_day=False,
        starts_at="2026-10-01T23:30:00Z",
        ends_at="2026-10-01T23:45:00Z",
    )
    first = {"from": "2026-10-01", "to": "2026-10-02"}

    assert titles(group_calendar(client, owner, group["id"], **first, tz="UTC")) == [
        "Midnight snack"
    ]
    assert titles(group_calendar(client, owner, group["id"], **first, tz="Europe/Bucharest")) == []


# --- filters --------------------------------------------------------------------------------


def test_kinds_filter_and_birthday_covers_member_birthdays(
    client: TestClient, owner: Account, group: dict[str, Any]
) -> None:
    set_birthday(client, owner, 10, 5)
    create_event(client, owner, group["id"], title="Picnic", start_date="2026-10-03")
    create_event(
        client, owner, group["id"], title="Grandma", kind="birthday", start_date="1950-10-04"
    )
    create_event(
        client,
        owner,
        group["id"],
        title="Yoga",
        kind="recurring",
        start_date="2026-10-01",
        rrule="FREQ=WEEKLY",
    )
    october = {"from": "2026-10-01", "to": "2026-10-08"}

    everything = group_calendar(client, owner, group["id"], **october)
    birthdays = group_calendar(client, owner, group["id"], **october, kinds="birthday")
    plans = group_calendar(client, owner, group["id"], **october, kinds=["one_time", "recurring"])

    assert titles(everything) == ["Yoga", "Picnic", "Grandma", "Olga"]
    assert titles(birthdays) == ["Grandma", "Olga"]
    assert [o["source"] for o in birthdays["occurrences"]] == ["event", "member_birthday"]
    assert titles(plans) == ["Yoga", "Picnic"]


def test_category_filter_includes_subcategories_and_excludes_member_birthdays(
    client: TestClient, owner: Account, group: dict[str, Any]
) -> None:
    set_birthday(client, owner, 10, 5)
    movies = next(
        c for c in list_categories(client, owner, group["id"]) if c["name"] == "Movie night"
    )
    horror = create_category(client, owner, group["id"], name="Horror", parent_id=movies["id"])
    games = next(c for c in list_categories(client, owner, group["id"]) if c["name"] == "Games")
    create_event(client, owner, group["id"], title="Dune", category_id=movies["id"])
    create_event(client, owner, group["id"], title="Alien", category_id=horror["id"])
    create_event(client, owner, group["id"], title="Catan", category_id=games["id"])
    create_event(client, owner, group["id"], title="Plain")
    october = {"from": "2026-10-01", "to": "2026-10-08"}

    body = group_calendar(client, owner, group["id"], **october, category_id=movies["id"])
    sub = group_calendar(client, owner, group["id"], **october, category_id=horror["id"])

    assert titles(body) == ["Alien", "Dune"]
    assert {o["color"] for o in body["occurrences"]} == {"#7E57C2"}  # the subcategory inherits
    assert titles(sub) == ["Alien"]


# --- member birthdays -----------------------------------------------------------------------


def test_member_birthdays_are_virtual_all_day_occurrences(
    client: TestClient, owner: Account, group: dict[str, Any]
) -> None:
    friend = add_member(client, owner, group["id"])
    set_birthday(client, friend, 10, 2, year=1990)

    body = group_calendar(client, owner, group["id"], **{"from": "2026-10-01", "to": "2027-11-01"})

    friend_name = client.get("/api/v1/me", headers=friend.headers).json()["display_name"]
    assert [o for o in body["occurrences"] if o["source"] == "member_birthday"] == [
        {
            "occurrence_key": key,
            "source": "member_birthday",
            "event_id": None,
            "user_id": friend.id,
            "group_id": group["id"],
            "kind": "birthday",
            "title": friend_name,
            "all_day": True,
            "starts_at": None,
            "ends_at": None,
            "start_date": day,
            "end_date": day,
            "timezone": None,
            "category_id": None,
            "color": None,
            "activity_id": None,
            "is_recurring": True,
            "can_edit": False,
        }
        for key, day in (("20261002", "2026-10-02"), ("20271002", "2027-10-02"))
    ]
    assert "1990" not in str(body)


def test_hidden_birthdays_are_left_out(
    client: TestClient, owner: Account, group: dict[str, Any]
) -> None:
    friend = add_member(client, owner, group["id"])
    set_birthday(client, friend, 10, 2)
    show_birthday(client, friend, group["id"], show=False)

    body = group_calendar(client, owner, group["id"], **{"from": "2026-10-01", "to": "2026-10-31"})

    assert body["occurrences"] == []


def test_a_29_february_birthday_falls_on_28_february_in_other_years(
    client: TestClient, owner: Account, group: dict[str, Any]
) -> None:
    set_birthday(client, owner, 2, 29)

    days = [
        o["start_date"]
        for year in (2027, 2028)
        for o in group_calendar(
            client, owner, group["id"], **{"from": f"{year}-01-01", "to": f"{year + 1}-01-01"}
        )["occurrences"]
    ]

    assert days == ["2027-02-28", "2028-02-29"]


def test_former_members_birthdays_are_gone(
    client: TestClient, owner: Account, group: dict[str, Any]
) -> None:
    friend = add_member(client, owner, group["id"])
    set_birthday(client, friend, 10, 2)
    left = client.delete(
        f"/api/v1/groups/{group['id']}/members/{friend.id}", headers=friend.headers
    )
    assert left.status_code == 204

    body = group_calendar(client, owner, group["id"], **{"from": "2026-10-01", "to": "2026-10-31"})

    assert body["occurrences"] == []


# --- ordering -------------------------------------------------------------------------------


def test_sort_order(client: TestClient, owner: Account, group: dict[str, Any]) -> None:
    create_event(
        client,
        owner,
        group["id"],
        title="Dinner",
        all_day=False,
        starts_at="2026-10-03T17:00:00Z",
        ends_at="2026-10-03T19:00:00Z",
    )
    create_event(
        client,
        owner,
        group["id"],
        title="Brunch",
        all_day=False,
        starts_at="2026-10-03T08:00:00Z",
        ends_at="2026-10-03T10:00:00Z",
    )
    create_event(
        client,
        owner,
        group["id"],
        title="Another brunch",
        all_day=False,
        starts_at="2026-10-03T08:00:00Z",
        ends_at="2026-10-03T09:00:00Z",
    )
    create_event(client, owner, group["id"], title="Saturday", start_date="2026-10-03")
    create_event(client, owner, group["id"], title="Friday", start_date="2026-10-02")
    create_event(
        client,
        owner,
        group["id"],
        title="Long weekend",
        start_date="2026-10-01",
        end_date="2026-10-04",
    )

    body = group_calendar(
        client,
        owner,
        group["id"],
        **{"from": "2026-10-02", "to": "2026-10-05"},
        tz="Europe/Bucharest",
    )

    assert titles(body) == [
        "Long weekend",  # starts earliest (1 October), still covers the range
        "Friday",
        "Saturday",  # all-day before timed on the same local date
        "Another brunch",  # same instant: by title
        "Brunch",
        "Dinner",
    ]


# --- /me/calendar ---------------------------------------------------------------------------


def test_my_calendar_spans_my_groups_and_deduplicates_birthdays(
    client: TestClient, owner: Account, group: dict[str, Any]
) -> None:
    other = create_group(client, owner, name="Climbing", timezone="UTC")
    friend = add_member(client, owner, group["id"])
    # The friend is in both groups but only shows the birthday in the second one.
    invite = client.post(
        f"/api/v1/groups/{other['id']}/invites", headers=owner.headers, json={}
    ).json()
    assert (
        client.post(f"/api/v1/invites/{invite['code']}/accept", headers=friend.headers).status_code
        == 200
    )
    set_birthday(client, friend, 10, 2)
    show_birthday(client, friend, group["id"], show=False)
    stranger = register(client)
    set_birthday(client, stranger, 10, 2)
    create_event(client, owner, group["id"], title="Picnic", start_date="2026-10-03")
    create_event(client, owner, other["id"], title="Bouldering", start_date="2026-10-04")

    body = my_calendar(client, owner, **{"from": "2026-10-01", "to": "2026-10-08"})

    assert titles(body)[1:] == ["Picnic", "Bouldering"]
    birthday, picnic, bouldering = body["occurrences"]
    assert (birthday["source"], birthday["user_id"], birthday["group_id"]) == (
        "member_birthday",
        friend.id,
        None,
    )
    assert picnic["group_id"] == group["id"]
    assert bouldering["group_id"] == other["id"]
    assert body["tz"] == "Europe/Bucharest"


def test_my_calendar_hides_birthdays_nobody_shares_with_me(client: TestClient) -> None:
    alone = register(client)
    set_birthday(client, alone, 10, 2)

    body = my_calendar(client, alone, **{"from": "2026-10-01", "to": "2026-10-08"})
    with_group = my_calendar(
        client, alone, **{"from": "2026-10-01", "to": "2026-10-08"}, kinds="one_time"
    )

    assert body["occurrences"] == []
    assert with_group["occurrences"] == []
