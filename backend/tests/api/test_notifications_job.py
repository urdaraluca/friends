"""The notification job (contract section 18.4): ``send-notifications``. Push is the main
channel; email only when switched on, to a verified address."""

import json
from datetime import UTC, datetime, timedelta
from itertools import count
from typing import Any
from zoneinfo import ZoneInfo

from cryptography.hazmat.primitives.asymmetric import ec
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from friends_api.core.config import Settings
from friends_api.core.db import utcnow
from friends_api.core.mail import RecordingMailer
from friends_api.core.webpush import RecordingPusher, _raw_public, b64url_encode
from friends_api.features.notifications.service import JobReport, send_notifications
from tests.api.test_calendar import set_birthday, show_birthday
from tests.api.test_wheel import accept, spun
from tests.factories import (
    Account,
    add_member,
    create_activity,
    create_event,
    create_group,
    create_poll,
    link_token,
    register,
    verify_email,
)

_endpoints = count(1)
P256DH = b64url_encode(_raw_public(ec.generate_private_key(ec.SECP256R1()).public_key()))
AUTH = b64url_encode(b"0123456789abcdef")


class Outbox:
    def __init__(self) -> None:
        self.mailer = RecordingMailer()
        self.pusher = RecordingPusher()
        self.report = JobReport()

    def pushes(self) -> list[tuple[str, dict[str, Any]]]:
        return [(t.endpoint, json.loads(p)) for t, p in self.pusher.pushed]


def run(
    db: Session, settings: Settings, now: datetime | None = None, *, gone: set[str] | None = None
) -> Outbox:
    outbox = Outbox()
    outbox.pusher.gone = gone or set()
    outbox.report = send_notifications(db, settings, outbox.mailer, outbox.pusher, now or utcnow())
    db.expire_all()
    return outbox


def subscribe(client: TestClient, account: Account) -> str:
    endpoint = f"https://fcm.googleapis.com/fcm/send/device-{next(_endpoints)}"
    response = client.put(
        "/api/v1/me/push-subscription",
        headers=account.headers,
        json={"endpoint": endpoint, "keys": {"p256dh": P256DH, "auth": AUTH}},
    )
    assert response.status_code == 204, response.text
    return endpoint


def set_prefs(client: TestClient, account: Account, **changes: bool) -> None:
    prefs = client.get("/api/v1/me/notifications", headers=account.headers).json()
    response = client.put(
        "/api/v1/me/notifications", headers=account.headers, json={**prefs, **changes}
    )
    assert response.status_code == 200, response.text


def crew(
    client: TestClient, db: Session, settings: Settings
) -> tuple[Account, Account, Account, str, dict[str, str]]:
    """An owner and two members, each with a browser subscribed; the group. The "joined"
    notices the setup causes are already sent."""
    owner = register(client, display_name="Ana")
    group = create_group(client, owner, name="Hikers")
    bea = add_member(client, owner, group["id"])
    cid = add_member(client, owner, group["id"])
    devices = {a.id: subscribe(client, a) for a in (owner, bea, cid)}
    run(db, settings)
    return owner, bea, cid, group["id"], devices


def test_a_new_poll_is_pushed_to_the_others_once(
    client: TestClient, db_session: Session, settings: Settings
) -> None:
    owner, bea, cid, group_id, devices = crew(client, db_session, settings)
    activity = create_activity(client, owner, group_id, title="Dune")
    create_poll(client, owner, activity["id"], question="Friday or Saturday?")

    outbox = run(db_session, settings)

    assert sorted(e for e, _ in outbox.pushes()) == sorted([devices[bea.id], devices[cid.id]])
    payload = outbox.pushes()[0][1]
    assert payload["title"] == "New poll in Hikers: Friday or Saturday?"
    assert payload["body"] == "Ana started a poll on Dune."
    assert payload["url"].endswith(f"/groups/{group_id}/backlog/{activity['id']}")
    assert outbox.mailer.sent == []  # email is opt-in
    assert run(db_session, settings).pusher.pushed == []  # not twice


def test_email_only_when_switched_on_and_verified(
    client: TestClient, mailer: RecordingMailer, db_session: Session, settings: Settings
) -> None:
    owner, bea, cid, group_id, _devices = crew(client, db_session, settings)
    set_prefs(client, bea, email=True)
    verify_email(client, bea, mailer)
    set_prefs(client, cid, email=True)  # not verified: no email
    create_poll(client, owner, create_activity(client, owner, group_id, title="Dune")["id"])

    outbox = run(db_session, settings)

    assert [e.to for e in outbox.mailer.sent] == [bea.email]
    email = outbox.mailer.sent[0]
    assert email.headers["List-Unsubscribe-Post"] == "List-Unsubscribe=One-Click"
    assert len(outbox.pusher.pushed) == 2  # push as well


def test_unsubscribing_from_an_email_turns_that_kind_off(
    client: TestClient, mailer: RecordingMailer, db_session: Session, settings: Settings
) -> None:
    owner, bea, _cid, group_id, _devices = crew(client, db_session, settings)
    set_prefs(client, bea, email=True)
    verify_email(client, bea, mailer)
    activity = create_activity(client, owner, group_id)
    create_poll(client, owner, activity["id"])
    email = run(db_session, settings).mailer.sent[0]

    token = link_token(email.text.split("Unsubscribe:")[1])
    response = client.post("/api/v1/notifications/unsubscribe", params={"token": token})
    assert response.json() == {"kind": "polls"}
    create_poll(client, owner, activity["id"])

    outbox = run(db_session, settings)
    assert outbox.mailer.sent == []
    assert len(outbox.pusher.pushed) == 1  # cid's browser; bea turned polls off everywhere


def test_muting_a_group_and_switching_a_kind_off(
    client: TestClient, db_session: Session, settings: Settings
) -> None:
    owner, bea, cid, group_id, devices = crew(client, db_session, settings)
    muted = client.put(
        f"/api/v1/groups/{group_id}/members/me/settings",
        headers=bea.headers,
        json={"show_birthday": True, "notifications_muted": True},
    )
    assert muted.json()["notifications_muted"] is True
    set_prefs(client, cid, polls=False)
    create_poll(client, owner, create_activity(client, owner, group_id)["id"])

    assert run(db_session, settings).pusher.pushed == []
    assert devices  # both had browsers subscribed


def test_wheel_results(client: TestClient, db_session: Session, settings: Settings) -> None:
    owner, _bea, _cid, group_id, _devices = crew(client, db_session, settings)
    first = create_activity(client, owner, group_id, title="Bowling")
    second = create_activity(client, owner, group_id, title="Karaoke")

    spin = spun(client, owner, group_id, activity_ids=[first["id"], second["id"]])
    assert run(db_session, settings).pusher.pushed == []  # spun, not accepted yet
    assert accept(client, owner, spin["id"]).status_code == 200
    outbox = run(db_session, settings)

    picked = next(c["title"] for c in spin["candidates"] if c["id"] == spin["result"]["id"])
    assert [p["title"] for _, p in outbox.pushes()] == [f"The wheel picked {picked} in Hikers"] * 2


def test_a_plan_for_an_activity_im_interested_in(
    client: TestClient, db_session: Session, settings: Settings
) -> None:
    owner, bea, _cid, group_id, devices = crew(client, db_session, settings)
    activity = create_activity(client, owner, group_id, title="Bowling")
    client.put(f"/api/v1/activities/{activity['id']}/interest", headers=bea.headers)

    create_event(client, owner, group_id, title="Bowling night", activity_id=activity["id"])
    outbox = run(db_session, settings)

    assert [(e, p["title"]) for e, p in outbox.pushes()] == [
        (devices[bea.id], "Bowling is happening in Hikers")  # not cid: not interested
    ]


def test_someone_joining_is_announced(
    client: TestClient, db_session: Session, settings: Settings
) -> None:
    owner = register(client)
    group = create_group(client, owner, name="Hikers")
    device = subscribe(client, owner)
    run(db_session, settings)
    newcomer = add_member(client, owner, group["id"])
    name = client.get("/api/v1/me", headers=newcomer.headers).json()["display_name"]

    outbox = run(db_session, settings)

    assert [(e, p["title"]) for e, p in outbox.pushes()] == [(device, f"{name} joined Hikers")]


def test_gone_subscriptions_are_removed(
    client: TestClient, db_session: Session, settings: Settings
) -> None:
    owner, _bea, _cid, group_id, devices = crew(client, db_session, settings)
    create_poll(client, owner, create_activity(client, owner, group_id)["id"])
    gone = set(devices.values())

    first = run(db_session, settings, gone=gone)
    create_poll(client, owner, create_activity(client, owner, group_id)["id"])
    second = run(db_session, settings)

    assert first.report.failed == 2
    assert second.pusher.pushed == []  # those subscriptions were deleted


def test_a_poll_closing_soon_reminds_those_who_havent_voted(
    client: TestClient, db_session: Session, settings: Settings
) -> None:
    owner, bea, cid, group_id, devices = crew(client, db_session, settings)
    closes = (utcnow() + timedelta(hours=30)).isoformat()
    poll = create_poll(
        client, owner, create_activity(client, owner, group_id)["id"], closes_at=closes
    )
    run(db_session, settings)  # "new poll"
    vote = client.put(
        f"/api/v1/polls/{poll['id']}/votes/me",
        headers=bea.headers,
        json={"option_ids": [poll["options"][0]["id"]]},
    )
    assert vote.status_code == 200, vote.text

    assert run(db_session, settings).pusher.pushed == []  # 30 hours left
    outbox = run(db_session, settings, utcnow() + timedelta(hours=10))

    assert sorted(e for e, _ in outbox.pushes()) == sorted([devices[owner.id], devices[cid.id]])
    assert outbox.pushes()[0][1]["title"].startswith("Last day to vote in Hikers")


def test_old_log_entries_are_skipped(
    client: TestClient, db_session: Session, settings: Settings
) -> None:
    owner, _bea, _cid, group_id, _devices = crew(client, db_session, settings)
    create_poll(client, owner, create_activity(client, owner, group_id)["id"])

    assert run(db_session, settings, utcnow() + timedelta(hours=7)).pusher.pushed == []


def test_reminders_a_day_and_an_hour_before(
    client: TestClient, mailer: RecordingMailer, db_session: Session, settings: Settings
) -> None:
    owner = register(client)
    group_id = create_group(client, owner, name="Hikers")["id"]
    device = subscribe(client, owner)
    set_prefs(client, owner, email=True)
    verify_email(client, owner, mailer)
    now = datetime(2026, 10, 14, 17, 0, tzinfo=UTC)

    def timed(title: str, start: datetime) -> None:
        create_event(
            client,
            owner,
            group_id,
            title=title,
            all_day=False,
            starts_at=start.isoformat(),
            ends_at=(start + timedelta(hours=2)).isoformat(),
        )

    timed("Game night", now + timedelta(hours=23))
    timed("Too far", now + timedelta(hours=25))

    day_before = run(db_session, settings, now)
    assert [p["title"] for _, p in day_before.pushes()] == [
        "Coming up: Game night, tomorrow at 16:00"  # the owner's zone: UTC
    ]
    assert [e.subject for e in day_before.mailer.sent] == [
        "Coming up: Game night, tomorrow at 16:00"
    ]
    assert run(db_session, settings, now + timedelta(minutes=5)).pusher.pushed == []

    hour_before = run(db_session, settings, now + timedelta(hours=22, minutes=30))
    assert sorted(p["title"] for _, p in hour_before.pushes()) == [
        "Coming up: Game night, today at 16:00",  # an hour before, push only
        "Coming up: Too far, today at 18:00",  # now within the day
    ]
    assert {e for e, _ in hour_before.pushes()} == {device}
    assert [e.subject for e in hour_before.mailer.sent] == ["Coming up: Too far, today at 18:00"]


def test_all_day_reminders_start_the_evening_before_in_my_timezone(
    client: TestClient, db_session: Session, settings: Settings
) -> None:
    owner = register(client, timezone="Europe/Bucharest")
    subscribe(client, owner)
    group_id = create_group(client, owner, name="Hikers")["id"]
    create_event(client, owner, group_id, title="Hike", start_date="2026-10-15")
    bucharest = ZoneInfo("Europe/Bucharest")

    early = run(db_session, settings, datetime(2026, 10, 14, 17, 59, tzinfo=bucharest))
    evening = run(db_session, settings, datetime(2026, 10, 14, 18, 0, tzinfo=bucharest))

    assert early.pusher.pushed == []
    ((_, payload),) = evening.pushes()
    assert payload["title"] == "Coming up: Hike, tomorrow"
    assert payload["body"] == "• Hike, tomorrow (Hikers)"


def test_birthdays_but_not_my_own_and_several_in_one(
    client: TestClient, db_session: Session, settings: Settings
) -> None:
    owner, bea, _cid, group_id, devices = crew(client, db_session, settings)
    set_birthday(client, bea, 10, 15)
    show_birthday(client, bea, group_id, show=True)
    create_event(client, owner, group_id, title="Picnic", start_date="2026-10-15")
    name = client.get("/api/v1/me", headers=bea.headers).json()["display_name"]

    outbox = run(db_session, settings, datetime(2026, 10, 14, 20, 0, tzinfo=UTC))

    by_device = dict(outbox.pushes())
    assert by_device[devices[owner.id]]["title"] == "Coming up: 2 things in your calendar"
    assert f"🎂 {name}'s birthday" in by_device[devices[owner.id]]["body"]
    assert by_device[devices[bea.id]]["title"] == "Coming up: Picnic, tomorrow"


def test_subscriptions_only_for_known_push_services(client: TestClient) -> None:
    account = register(client)
    body = {"endpoint": "https://169.254.169.254/latest", "keys": {"p256dh": P256DH, "auth": AUTH}}

    response = client.put("/api/v1/me/push-subscription", headers=account.headers, json=body)
    bad_keys = client.put(
        "/api/v1/me/push-subscription",
        headers=account.headers,
        json={
            "endpoint": "https://updates.push.services.mozilla.com/wpush/v2/x",
            "keys": {"p256dh": "abc", "auth": AUTH},
        },
    )

    assert response.status_code == 422
    assert response.json()["errors"][0]["field"] == "body.endpoint"
    assert bad_keys.status_code == 422
    config = client.get("/api/v1/push/config", headers=account.headers).json()
    assert config == {"public_key": "test-public-key"}


def test_turning_push_off_for_a_browser(
    client: TestClient, db_session: Session, settings: Settings
) -> None:
    owner, bea, _cid, group_id, devices = crew(client, db_session, settings)
    response = client.delete(
        "/api/v1/me/push-subscription",
        headers=bea.headers,
        params={"endpoint": devices[bea.id]},
    )
    assert response.status_code == 204
    create_poll(client, owner, create_activity(client, owner, group_id)["id"])

    assert devices[bea.id] not in [e for e, _ in run(db_session, settings).pushes()]
