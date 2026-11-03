"""The webcal feed (contract section 5.10): ``/me/calendar-feed`` and the public
``/calendar-feed/{token}.ics``."""

import logging
from typing import Any

import pytest
import time_machine
from fastapi.testclient import TestClient

from tests.api.test_calendar import WEEKLY_THURSDAY_1900_BUCHAREST, set_birthday, show_birthday
from tests.factories import Account, add_member, create_event, create_group, register

NOW = "2026-10-05T10:00:00Z"
GAME_NIGHT = r"SUMMARY:Game night\; bring snacks"


def enable(client: TestClient, account: Account) -> dict[str, Any]:
    response = client.post("/api/v1/me/calendar-feed", headers=account.headers)
    assert response.status_code == 200, response.text
    body: dict[str, Any] = response.json()
    return body


def feed_path(feed: dict[str, Any]) -> str:
    return "/api/v1/" + str(feed["url"]).split("/api/v1/", 1)[1]


def unfold(ics: str) -> list[str]:
    return ics.replace("\r\n ", "").split("\r\n")


def test_the_feed_is_off_until_enabled(client: TestClient) -> None:
    me = register(client)

    off = client.get("/api/v1/me/calendar-feed", headers=me.headers).json()
    feed = enable(client, me)

    assert off == {"url": None, "webcal_url": None}
    assert feed["url"].startswith("http://localhost:5000/api/v1/calendar-feed/")
    assert feed["url"].endswith(".ics")
    assert feed["webcal_url"] == "webcal://" + feed["url"].removeprefix("http://")
    assert client.get("/api/v1/me/calendar-feed", headers=me.headers).json() == feed


def test_resetting_or_disabling_revokes_the_old_url(client: TestClient) -> None:
    me = register(client)
    first = enable(client, me)
    second = enable(client, me)

    assert second["url"] != first["url"]
    assert client.get(feed_path(first)).status_code == 404
    assert client.get(feed_path(second)).status_code == 200

    assert client.delete("/api/v1/me/calendar-feed", headers=me.headers).status_code == 204
    assert client.get(feed_path(second)).status_code == 404
    off = client.get("/api/v1/me/calendar-feed", headers=me.headers).json()
    assert off["url"] is None


def test_unknown_tokens_are_not_found(client: TestClient) -> None:
    assert client.get("/api/v1/calendar-feed/nope.ics").status_code == 404


def test_the_feed_needs_no_sign_in_and_lists_my_occurrences(client: TestClient) -> None:
    me = register(client, timezone="Europe/Bucharest")
    group = create_group(client, me, name="Board games, Thursdays")
    create_event(
        client, me, group["id"], title="Game night; bring snacks", **WEEKLY_THURSDAY_1900_BUCHAREST
    )
    create_event(
        client, me, group["id"], title="Trip", start_date="2026-10-10", end_date="2026-10-11"
    )
    feed = enable(client, me)

    with time_machine.travel(NOW, tick=False):
        response = client.get(feed_path(feed))

    assert response.status_code == 200
    assert response.headers["content-type"] == "text/calendar; charset=utf-8"
    lines = unfold(response.text)
    assert lines[0] == "BEGIN:VCALENDAR"
    assert lines[-2:] == ["END:VCALENDAR", ""]
    assert "X-WR-CALNAME:Friends" in lines
    assert GAME_NIGHT in lines
    assert r"DESCRIPTION:Board games\, Thursdays" in lines
    # Weekly from 1 October, within [today - 30 days, today + 365 days).
    assert "DTSTART:20261001T160000Z" in lines
    assert "DTEND:20261001T190000Z" in lines
    assert lines.count(GAME_NIGHT) == 53
    # All-day: DTEND is the day after the last day.
    trip = lines.index("SUMMARY:Trip")
    assert "DTSTART;VALUE=DATE:20261010" in lines[trip - 4 : trip]
    assert "DTEND;VALUE=DATE:20261012" in lines[trip - 4 : trip]
    assert all(len(line.encode()) <= 75 for line in response.text.split("\r\n"))


def test_cancelled_occurrences_are_left_out(client: TestClient) -> None:
    me = register(client)
    group = create_group(client, me)
    event = create_event(client, me, group["id"], title="Weekly", **WEEKLY_THURSDAY_1900_BUCHAREST)
    cancel = client.delete(
        f"/api/v1/events/{event['id']}/occurrences/20261008T160000Z", headers=me.headers
    )
    assert cancel.status_code == 204
    feed = enable(client, me)

    with time_machine.travel(NOW, tick=False):
        lines = unfold(client.get(feed_path(feed)).text)

    assert "DTSTART:20261001T160000Z" in lines
    assert "DTSTART:20261008T160000Z" not in lines
    assert f"UID:{event['id']}-20261015T160000Z@friends.calendar" in lines


def test_member_birthdays_get_a_cake(client: TestClient) -> None:
    me = register(client)
    group = create_group(client, me)
    friend = add_member(client, me, group["id"])
    set_birthday(client, friend, 10, 20, 1990)
    show_birthday(client, friend, group["id"], show=True)
    friend_name = client.get("/api/v1/me", headers=friend.headers).json()["display_name"]
    feed = enable(client, me)

    with time_machine.travel(NOW, tick=False):
        lines = unfold(client.get(feed_path(feed)).text)

    assert f"SUMMARY:🎂 {friend_name}" in lines
    assert "DTSTART;VALUE=DATE:20261020" in lines
    assert not any("1990" in line for line in lines)


def test_the_token_is_masked_in_the_access_log(
    client: TestClient, caplog: pytest.LogCaptureFixture
) -> None:
    me = register(client)
    feed = enable(client, me)
    token = feed["url"].rsplit("/", 1)[1]

    with caplog.at_level(logging.INFO, logger="friends_api.access"):
        client.get(feed_path(feed))

    access = [r.getMessage() for r in caplog.records if r.name == "friends_api.access"]
    assert not any(token in line for line in access)
    assert any(line.startswith("GET /api/v1/calendar-feed/*** 200 ") for line in access)


def test_deleting_the_account_turns_the_feed_off(client: TestClient) -> None:
    me = register(client)
    feed = enable(client, me)

    response = client.post(
        "/api/v1/me/deletion", headers=me.headers, json={"password": me.password}
    )

    assert response.status_code == 204
    assert client.get(feed_path(feed)).status_code == 404
