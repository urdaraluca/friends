"""seed-demo's calendar step (issue #12): every kind of event, profile birthdays, a cancelled
occurrence, and an idea scheduled by an event."""

from collections import Counter
from datetime import UTC, date, datetime, timedelta

import pytest
import time_machine
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from friends_api import cli
from friends_api.core.config import Settings
from friends_api.demo.context import DEMO_EMAILS, DEMO_PASSWORD
from friends_api.features.activities.models import Activity, ActivityStatus
from friends_api.features.auth.models import User
from friends_api.features.events.models import Event, EventException, EventKind
from friends_api.features.groups.models import Group
from tests.factories import bearer, login


@pytest.mark.parametrize(
    "now",
    [
        datetime(2026, 10, 1, 9, tzinfo=UTC),
        datetime(2027, 1, 29, 23, tzinfo=UTC),  # the swap's Sunday may fall late in the month
        datetime(2028, 2, 29, 12, tzinfo=UTC),
    ],
)
def test_seed_demo_creates_the_calendar(
    settings: Settings, db_session: Session, now: datetime
) -> None:

    with time_machine.travel(now, tick=False):
        assert cli.main(["seed-demo"], settings) == 0

    events = db_session.scalars(select(Event)).all()
    kinds = Counter(event.kind for event in events)
    assert kinds[EventKind.ONE_TIME] == 2
    assert kinds[EventKind.RECURRING] == 4
    assert kinds[EventKind.BIRTHDAY] == 2
    rules = {event.title: event.rrule for event in events}
    assert rules["Game night"] == "FREQ=WEEKLY;BYDAY=TH"
    assert rules["Dinner club"] == "FREQ=MONTHLY;BYDAY=-1FR"
    assert rules["Anniversary picnic"] == "FREQ=YEARLY"
    assert rules["Mihai"] == "FREQ=YEARLY"
    assert db_session.scalars(select(EventException)).one()

    users = db_session.scalars(select(User).order_by(User.email)).all()
    assert [(u.birthday_month, u.birthday_day) for u in users] == [(3, 14), (10, 21), (2, 29)]

    linked = [event.activity_id for event in events if event.activity_id is not None]
    assert linked
    statuses = {
        a.status for a in db_session.scalars(select(Activity).where(Activity.id.in_(linked)))
    }
    assert statuses == {ActivityStatus.SCHEDULED}


def test_the_demo_calendar_is_served(
    settings: Settings, client: TestClient, db_session: Session
) -> None:
    assert cli.main(["seed-demo"], settings) == 0
    group_id = db_session.scalars(select(Group.id)).one()
    headers = bearer(login(client, DEMO_EMAILS[2], DEMO_PASSWORD)["tokens"]["access_token"])
    today = datetime.now(UTC).date()
    start = date(today.year, today.month, 1)

    response = client.get(
        f"/api/v1/groups/{group_id}/calendar",
        headers=headers,
        params={
            "from": start.isoformat(),
            "to": (start + timedelta(days=400)).isoformat(),
            "tz": "Europe/Bucharest",
        },
    )

    assert response.status_code == 200, response.text
    occurrences = response.json()["occurrences"]
    sources = Counter(o["source"] for o in occurrences)
    assert sources["member_birthday"] >= 3  # one per demo user within 400 days
    titles = {o["title"] for o in occurrences}
    assert {"Game night", "Dinner club", "Anniversary picnic", "Grandma Elena"} <= titles
    assert len([o for o in occurrences if o["title"] == "Game night"]) > 50
