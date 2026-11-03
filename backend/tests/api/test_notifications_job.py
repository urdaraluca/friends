"""The notification job (contract section 18.4): ``send-notifications``."""

from datetime import UTC, datetime, timedelta
from zoneinfo import ZoneInfo

from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from friends_api.core.config import Settings
from friends_api.core.db import utcnow
from friends_api.core.mail import RecordingMailer
from friends_api.features.notifications.service import send_notifications
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


def run(db: Session, settings: Settings, now: datetime | None = None) -> RecordingMailer:
    outbox = RecordingMailer()
    send_notifications(db, settings, outbox, now or utcnow())
    return outbox


def to(outbox: RecordingMailer) -> list[str]:
    return sorted(email.to for email in outbox.sent)


def crew(client: TestClient, mailer: RecordingMailer) -> tuple[Account, Account, Account, str]:
    """An owner and a member with verified addresses, a member without, and their group."""
    owner = register(client, display_name="Ana")
    group = create_group(client, owner, name="Hikers")
    verified = add_member(client, owner, group["id"])
    unverified = add_member(client, owner, group["id"])
    verify_email(client, owner, mailer)
    verify_email(client, verified, mailer)
    return owner, verified, unverified, group["id"]


def test_a_new_poll_goes_to_the_other_verified_members_once(
    client: TestClient, mailer: RecordingMailer, db_session: Session, settings: Settings
) -> None:
    owner, verified, _unverified, group_id = crew(client, mailer)
    activity = create_activity(client, owner, group_id, title="Dune")
    create_poll(client, owner, activity["id"], question="Friday or Saturday?")

    outbox = run(db_session, settings)

    assert to(outbox) == [verified.email]  # not the author, not the unverified member
    (email,) = outbox.sent
    assert email.subject == "New poll in Hikers: Friday or Saturday?"
    assert "Ana started a poll on Dune in Hikers:" in email.text
    assert f"/groups/{group_id}/backlog/{activity['id']}" in email.text
    assert email.headers["List-Unsubscribe-Post"] == "List-Unsubscribe=One-Click"
    assert "/api/v1/notifications/unsubscribe?token=" in email.headers["List-Unsubscribe"]
    assert run(db_session, settings).sent == []  # not twice


def test_switching_a_kind_off_or_unsubscribing_stops_it(
    client: TestClient, mailer: RecordingMailer, db_session: Session, settings: Settings
) -> None:
    owner, verified, _unverified, group_id = crew(client, mailer)
    activity = create_activity(client, owner, group_id)
    create_poll(client, owner, activity["id"])
    token = link_token(run(db_session, settings).sent[0].text.split("Unsubscribe:")[1])

    response = client.post("/api/v1/notifications/unsubscribe", params={"token": token})
    assert response.json() == {"kind": "polls"}
    create_poll(client, owner, activity["id"])
    db_session.expire_all()

    assert run(db_session, settings).sent == []
    prefs = client.get("/api/v1/me/notifications", headers=verified.headers).json()
    assert prefs["polls"] is False


def test_a_wheel_result_once_accepted(
    client: TestClient, mailer: RecordingMailer, db_session: Session, settings: Settings
) -> None:
    owner, verified, _unverified, group_id = crew(client, mailer)
    first = create_activity(client, owner, group_id, title="Bowling")
    second = create_activity(client, owner, group_id, title="Karaoke")
    spin = spun(client, owner, group_id, activity_ids=[first["id"], second["id"]])

    assert run(db_session, settings).sent == []  # spun, not accepted yet
    assert accept(client, owner, spin["id"]).status_code == 200
    outbox = run(db_session, settings)

    assert to(outbox) == [verified.email]
    title = next(c["title"] for c in spin["candidates"] if c["id"] == spin["result"]["id"])
    assert outbox.sent[0].subject == f"The wheel picked {title} in Hikers"


def test_log_entries_older_than_the_lookback_are_skipped(
    client: TestClient, mailer: RecordingMailer, db_session: Session, settings: Settings
) -> None:
    owner, _verified, _unverified, group_id = crew(client, mailer)
    create_poll(client, owner, create_activity(client, owner, group_id)["id"])

    assert run(db_session, settings, utcnow() + timedelta(hours=7)).sent == []


def test_reminders_for_timed_events_within_a_day(
    client: TestClient, mailer: RecordingMailer, db_session: Session, settings: Settings
) -> None:
    owner, verified, _unverified, group_id = crew(client, mailer)
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
    timed("Already started", now - timedelta(minutes=5))

    outbox = run(db_session, settings, now)

    assert to(outbox) == sorted([owner.email, verified.email])  # reminders include the author
    email = next(e for e in outbox.sent if e.to == owner.email)
    assert email.subject == "Coming up: Game night, tomorrow at 16:00"  # the owner's zone: UTC
    assert "Too far" not in email.text
    assert "Already started" not in email.text
    assert run(db_session, settings, now + timedelta(minutes=15)).sent == []
    assert len(run(db_session, settings, now + timedelta(hours=2)).sent) == 2  # "Too far" now


def test_all_day_reminders_start_the_evening_before_in_my_timezone(
    client: TestClient, mailer: RecordingMailer, db_session: Session, settings: Settings
) -> None:
    owner = register(client, timezone="Europe/Bucharest")
    verify_email(client, owner, mailer)
    group_id = create_group(client, owner, name="Hikers")["id"]
    create_event(client, owner, group_id, title="Hike", start_date="2026-10-15")
    bucharest = ZoneInfo("Europe/Bucharest")

    early = run(db_session, settings, datetime(2026, 10, 14, 17, 59, tzinfo=bucharest))
    evening = run(db_session, settings, datetime(2026, 10, 14, 18, 0, tzinfo=bucharest))

    assert early.sent == []
    (email,) = evening.sent
    assert email.subject == "Coming up: Hike, tomorrow"
    assert "• Hike, tomorrow (Hikers)" in email.text


def test_birthdays_but_not_my_own(
    client: TestClient, mailer: RecordingMailer, db_session: Session, settings: Settings
) -> None:
    owner, verified, _unverified, group_id = crew(client, mailer)
    set_birthday(client, verified, 10, 15)
    show_birthday(client, verified, group_id, show=True)
    name = client.get("/api/v1/me", headers=verified.headers).json()["display_name"]

    outbox = run(db_session, settings, datetime(2026, 10, 14, 20, 0, tzinfo=UTC))

    assert to(outbox) == [owner.email]
    assert outbox.sent[0].subject == f"Coming up: 🎂 {name}'s birthday, tomorrow"


def test_several_reminders_come_in_one_email(
    client: TestClient, mailer: RecordingMailer, db_session: Session, settings: Settings
) -> None:
    owner = register(client)
    verify_email(client, owner, mailer)
    group_id = create_group(client, owner)["id"]
    for title in ("Picnic", "Museum"):
        create_event(client, owner, group_id, title=title, start_date="2026-10-15")

    (email,) = run(db_session, settings, datetime(2026, 10, 14, 20, 0, tzinfo=UTC)).sent

    assert email.subject == "Coming up: 2 things in your calendar"
    assert "Picnic" in email.text
    assert "Museum" in email.text
