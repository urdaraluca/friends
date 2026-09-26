"""The group recap (contract section 14)."""

import uuid
from datetime import UTC, date, datetime, timedelta
from typing import Any
from zoneinfo import ZoneInfo

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select, update
from sqlalchemy.orm import Session

from friends_api.features.activities.models import Activity, ActivityInterest
from friends_api.features.group_log.models import GroupLog
from friends_api.features.polls.models import Poll
from friends_api.features.recap.schemas import RecapPeriod
from friends_api.features.recap.service import period_end, resolve_start
from friends_api.features.wheel.models import WheelSpin
from tests.factories import (
    Account,
    add_member,
    create_activity,
    create_category,
    create_event,
    create_group,
    create_poll,
    register,
)

BUCHAREST = "Europe/Bucharest"


def utc(year: int, month: int, day: int, hour: int = 0, minute: int = 0) -> datetime:
    return datetime(year, month, day, hour, minute, tzinfo=UTC)


def recap(client: TestClient, account: Account, group_id: str, **params: str) -> dict[str, Any]:
    response = client.get(
        f"/api/v1/groups/{group_id}/recap", headers=account.headers, params=params
    )
    assert response.status_code == 200, response.text
    body: dict[str, Any] = response.json()
    return body


def done(
    client: TestClient,
    db: Session,
    account: Account,
    group_id: str,
    completed_at: datetime,
    *,
    created_at: datetime | None = None,
    **fields: Any,
) -> dict[str, Any]:
    """An activity created as done, completed at ``completed_at``."""
    activity = create_activity(client, account, group_id, status="done", **fields)
    db.execute(
        update(Activity)
        .where(Activity.id == uuid.UUID(activity["id"]))
        .values(
            completed_at=completed_at,
            status_changed_at=completed_at,
            created_at=created_at or completed_at - timedelta(days=1),
        )
    )
    db.commit()
    return activity


def move_log(db: Session, group_id: str, when: datetime) -> None:
    """Moves every log row of the group to ``when``."""
    db.execute(
        update(GroupLog).where(GroupLog.group_id == uuid.UUID(group_id)).values(created_at=when)
    )
    db.commit()


@pytest.fixture
def owner(client: TestClient) -> Account:
    return register(client, display_name="Ana")


@pytest.fixture
def group(client: TestClient, owner: Account) -> dict[str, Any]:
    return create_group(client, owner, timezone=BUCHAREST)


# --- periods --------------------------------------------------------------------------------


def test_periods_are_calendar_months_and_years() -> None:
    assert period_end(RecapPeriod.MONTH, date(2025, 12, 1)) == date(2026, 1, 1)
    assert period_end(RecapPeriod.MONTH, date(2025, 2, 1)) == date(2025, 3, 1)
    assert period_end(RecapPeriod.YEAR, date(2025, 1, 1)) == date(2026, 1, 1)
    today = date(2026, 9, 26)
    assert resolve_start(RecapPeriod.MONTH, None, today) == date(2026, 9, 1)
    assert resolve_start(RecapPeriod.YEAR, None, today) == date(2026, 1, 1)
    assert resolve_start(RecapPeriod.MONTH, date(2026, 9, 1), today) == date(2026, 9, 1)


def test_memories_follow_the_groups_timezone(
    client: TestClient, db_session: Session, owner: Account, group: dict[str, Any]
) -> None:
    gid = group["id"]
    # October 2025 in Bucharest: 30 Sep 21:00 UTC to 31 Oct 22:00 UTC (DST ends on 26 October).
    first = done(client, db_session, owner, gid, utc(2025, 9, 30, 21, 30), title="First")
    done(client, db_session, owner, gid, utc(2025, 9, 30, 20, 30), title="September")
    last = done(client, db_session, owner, gid, utc(2025, 10, 31, 21, 30), title="Last")
    done(client, db_session, owner, gid, utc(2025, 10, 31, 22, 30), title="November")
    create_activity(client, owner, gid, title="Still an idea")

    body = recap(client, owner, gid, period="month", start="2025-10-01")

    assert body["period"] == "month"
    assert body["start"] == "2025-10-01"
    assert body["end"] == "2025-11-01"
    assert body["timezone"] == BUCHAREST
    assert body["complete"] is True
    assert body["memory_count"] == 2
    assert [m["id"] for m in body["memories"]] == [first["id"], last["id"]]
    assert body["memories"][0]["title"] == "First"
    september = recap(client, owner, gid, period="month", start="2025-09-01")
    assert [m["title"] for m in september["memories"]] == ["September"]
    year = recap(client, owner, gid, period="year", start="2025-01-01")
    assert year["memory_count"] == 4
    assert year["busiest_month"] == {"month": "2025-10-01", "count": 2}


def test_the_most_active_planners(
    client: TestClient, db_session: Session, owner: Account, group: dict[str, Any]
) -> None:
    gid = group["id"]
    bea = add_member(client, owner, gid)
    cris = add_member(client, owner, gid)
    # Ana: 1 idea and 1 marked done. Bea: 2 ideas, 1 event, 1 poll. Cris: nothing.
    idea = create_activity(client, owner, gid)
    for _ in range(2):
        create_activity(client, bea, gid)
    create_event(client, bea, gid)
    create_poll(client, bea, idea["id"])
    for status in ("planning", "done"):
        response = client.post(
            f"/api/v1/activities/{idea['id']}/status",
            headers=owner.headers,
            json={"status": status},
        )
        assert response.status_code == 200, response.text
    move_log(db_session, gid, utc(2025, 6, 15, 12))
    # A deleted account's rows (actor_id null) count in the totals, not for a planner.
    first_idea = db_session.scalars(
        select(GroupLog.id)
        .where(GroupLog.actor_id == uuid.UUID(bea.id), GroupLog.action == "activity.created")
        .limit(1)
    ).one()
    db_session.execute(update(GroupLog).where(GroupLog.id == first_idea).values(actor_id=None))
    db_session.commit()

    body = recap(client, cris, gid, period="month", start="2025-06-01")

    planners = [
        (p["user"]["id"], p["score"], p["ideas"], p["events"], p["polls"], p["done"])
        for p in body["planners"]
    ]
    assert planners == [(bea.id, 3, 1, 1, 1, 0), (owner.id, 2, 1, 0, 0, 1)]
    assert body["ideas_added"] == 3
    assert body["events_planned"] == 1
    assert body["polls_created"] == 1
    assert body["new_members"] == 3  # Ana created the group, Bea and Cris joined
    # Outside the period: nothing.
    empty = recap(client, cris, gid, period="month", start="2025-07-01")
    assert empty["planners"] == []
    assert empty["memory_count"] == 0
    assert empty["memories"] == []
    assert empty["longest_wait"] is None
    assert empty["top_categories"] == []


def test_top_categories_count_subcategories_under_their_parent(
    client: TestClient, db_session: Session, owner: Account, group: dict[str, Any]
) -> None:
    gid = group["id"]
    outdoors = create_category(client, owner, gid, name="Outdoor fun", color="#2E7D32")
    hiking = create_category(client, owner, gid, name="Mountain hikes", parent_id=outdoors["id"])
    food = create_category(client, owner, gid, name="Eating out", color="#EF6C00")
    when = utc(2025, 3, 10, 12)
    for category in (hiking, hiking, outdoors, food):
        done(client, db_session, owner, gid, when, category_id=category["id"])
    done(client, db_session, owner, gid, when)  # uncategorized

    body = recap(client, owner, gid, period="year", start="2025-01-01")

    assert [(c["name"], c["count"], c["color"]) for c in body["top_categories"]] == [
        ("Outdoor fun", 3, "#2E7D32"),
        ("Eating out", 1, "#EF6C00"),
    ]
    # A memory in a subcategory has its effective colour.
    colors = {m["category_id"]: m["color"] for m in body["memories"]}
    assert colors[hiking["id"]] == "#2E7D32"


def test_the_extras(
    client: TestClient, db_session: Session, owner: Account, group: dict[str, Any]
) -> None:
    gid = group["id"]
    bea = add_member(client, owner, gid)
    cris = add_member(client, owner, gid)
    in_may = utc(2025, 5, 20, 12)

    # The longest wait: created a year before it happened.
    patient = done(
        client, db_session, owner, gid, in_may, created_at=in_may - timedelta(days=400), title="Ski"
    )
    done(client, db_session, owner, gid, in_may, created_at=in_may - timedelta(days=3))

    # Polls: the one with the most voters wins; one created outside the period doesn't count.
    host = create_activity(client, owner, gid, title="Movie night")
    popular = create_poll(client, owner, host["id"], question="Which film?")
    quiet = create_poll(client, owner, host["id"], question="Snacks?")
    older = create_poll(client, owner, host["id"], question="Older?")
    for account in (owner, bea, cris):
        client.put(
            f"/api/v1/polls/{popular['id']}/votes/me",
            headers=account.headers,
            json={"option_ids": [popular["options"][0]["id"]]},
        )
        client.put(
            f"/api/v1/polls/{older['id']}/votes/me",
            headers=account.headers,
            json={"option_ids": [older["options"][0]["id"]]},
        )
    client.put(
        f"/api/v1/polls/{quiet['id']}/votes/me",
        headers=bea.headers,
        json={"option_ids": [quiet["options"][1]["id"]]},
    )
    for poll, when in ((popular, in_may), (quiet, in_may), (older, utc(2024, 5, 1))):
        db_session.execute(
            update(Poll).where(Poll.id == uuid.UUID(poll["id"])).values(created_at=when)
        )
    db_session.commit()

    # Most wanted: the backlog idea with the most interest by the end of the period.
    wanted = create_activity(client, owner, gid, title="Escape room")  # Ana, interested
    for account in (bea, cris):
        client.put(f"/api/v1/activities/{wanted['id']}/interest", headers=account.headers)
    late = create_activity(client, bea, gid, title="Karaoke")
    client.put(f"/api/v1/activities/{late['id']}/interest", headers=cris.headers)
    client.put(f"/api/v1/activities/{late['id']}/interest", headers=owner.headers)
    db_session.execute(
        update(Activity)
        .where(Activity.group_id == uuid.UUID(gid))
        .where(Activity.status != "done")
        .values(created_at=utc(2025, 1, 1))
    )
    db_session.execute(
        update(Activity)
        .where(Activity.id == uuid.UUID(late["id"]))
        .values(created_at=utc(2025, 1, 2))
    )
    db_session.execute(
        update(ActivityInterest)
        .where(ActivityInterest.activity_id == uuid.UUID(wanted["id"]))
        .values(created_at=utc(2025, 2, 1))
    )
    db_session.execute(  # Karaoke's interest came after May, except its creator's
        update(ActivityInterest)
        .where(
            ActivityInterest.activity_id == uuid.UUID(late["id"]),
            ActivityInterest.user_id != uuid.UUID(bea.id),
        )
        .values(created_at=utc(2025, 8, 1))
    )
    db_session.execute(
        update(ActivityInterest)
        .where(
            ActivityInterest.activity_id == uuid.UUID(late["id"]),
            ActivityInterest.user_id == uuid.UUID(bea.id),
        )
        .values(created_at=utc(2025, 2, 1))
    )

    # The wheel decided twice in May (and once in June).
    for accepted in (in_may, in_may + timedelta(days=1), utc(2025, 6, 2)):
        db_session.add(
            WheelSpin(
                group_id=uuid.UUID(gid),
                spun_by_id=uuid.UUID(owner.id),
                filters={},
                candidates=[],
                result_index=0,
                accepted_at=accepted,
                created_at=accepted,
            )
        )
    db_session.add(  # spun but never accepted
        WheelSpin(
            group_id=uuid.UUID(gid),
            filters={},
            candidates=[],
            result_index=0,
            created_at=in_may,
        )
    )
    db_session.commit()

    body = recap(client, owner, gid, period="month", start="2025-05-01")

    assert body["longest_wait"]["activity"]["id"] == patient["id"]
    assert body["longest_wait"]["days"] == 400
    assert body["top_poll"] == {
        "id": popular["id"],
        "question": "Which film?",
        "activity_id": host["id"],
        "activity_title": "Movie night",
        "voters": 3,
    }
    assert body["most_wanted"]["activity_id"] == wanted["id"]
    assert body["most_wanted"]["interested"] == 3
    assert body["wheel_decisions"] == 2
    assert body["busiest_month"] is None  # only for a year
    # By August, Karaoke has as much interest; the older idea wins the tie.
    august = recap(client, owner, gid, period="month", start="2025-08-01")
    assert august["most_wanted"]["activity_id"] == wanted["id"]
    # Once the idea is done, it's no longer wanted.
    client.post(
        f"/api/v1/activities/{wanted['id']}/status", headers=owner.headers, json={"status": "done"}
    )
    august = recap(client, owner, gid, period="month", start="2025-08-01")
    assert august["most_wanted"]["activity_id"] == late["id"]


def test_without_start_it_is_the_current_period(
    client: TestClient, owner: Account, group: dict[str, Any]
) -> None:
    today = datetime.now(ZoneInfo(BUCHAREST)).date()

    body = recap(client, owner, group["id"], period="month")

    assert body["start"] == today.replace(day=1).isoformat()
    assert body["complete"] is False
    year = recap(client, owner, group["id"], period="year")
    assert year["start"] == today.replace(month=1, day=1).isoformat()


@pytest.mark.parametrize(
    ("params", "message"),
    [
        ({"period": "month", "start": "2025-10-02"}, "Must be the first day of a month."),
        ({"period": "year", "start": "2025-10-01"}, "Must be the first day of a year."),
        ({"period": "year", "start": "1999-01-01"}, "Recaps start in 2000."),
        ({"period": "year", "start": "2999-01-01"}, "This period hasn't started yet."),
    ],
)
def test_invalid_starts(
    client: TestClient,
    owner: Account,
    group: dict[str, Any],
    params: dict[str, str],
    message: str,
) -> None:
    response = client.get(
        f"/api/v1/groups/{group['id']}/recap", headers=owner.headers, params=params
    )

    assert response.status_code == 422
    body = response.json()
    assert body["code"] == "validation_error"
    assert body["errors"] == [{"field": "query.start", "message": message, "type": "value_error"}]


def test_period_is_required(client: TestClient, owner: Account, group: dict[str, Any]) -> None:
    response = client.get(f"/api/v1/groups/{group['id']}/recap", headers=owner.headers)

    assert response.status_code == 422
    assert response.json()["errors"][0]["field"] == "query.period"
