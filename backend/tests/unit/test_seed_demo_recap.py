"""seed-demo's history step (issue #17): a year of history, and a yearly recap whose numbers
match the rows."""

import uuid
from collections import Counter
from datetime import UTC, datetime
from zoneinfo import ZoneInfo

import time_machine
from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from friends_api import cli
from friends_api.core.config import Settings
from friends_api.demo.context import DEMO_EMAILS, DEMO_PASSWORD, DEMO_TIMEZONE
from friends_api.features.activities.models import Activity, ActivityStatus
from friends_api.features.group_log.models import GroupLog
from friends_api.features.groups.models import Group
from friends_api.features.wheel.models import WheelSpin
from tests.factories import bearer, login

NOW = datetime(2026, 10, 1, 9, tzinfo=UTC)
# 2026 in Bucharest (the demo group's timezone).
BEGIN = datetime(2025, 12, 31, 22, tzinfo=UTC)
END = datetime(2026, 12, 31, 22, tzinfo=UTC)


def test_seed_demo_gives_a_year_of_recap(
    settings: Settings, client: TestClient, db_session: Session
) -> None:
    with time_machine.travel(NOW, tick=False):
        assert cli.main(["seed-demo"], settings) == 0
        group = db_session.scalars(select(Group)).one()
        headers = bearer(login(client, DEMO_EMAILS[2], DEMO_PASSWORD)["tokens"]["access_token"])
        response = client.get(
            f"/api/v1/groups/{group.id}/recap",
            headers=headers,
            params={"period": "year", "start": "2026-01-01"},
        )

    assert response.status_code == 200, response.text
    body = response.json()
    assert group.created_at < datetime(2025, 10, 1, tzinfo=UTC)  # a year of history

    done = db_session.scalars(
        select(Activity).where(
            Activity.group_id == group.id,
            Activity.status == ActivityStatus.DONE,
            Activity.completed_at >= BEGIN,
            Activity.completed_at < END,
        )
    ).all()
    assert body["memory_count"] == len(done) > 10
    assert body["complete"] is False
    months = Counter(
        a.completed_at.astimezone(ZoneInfo(DEMO_TIMEZONE)).date().replace(day=1)
        for a in done
        if a.completed_at
    )
    month, count = min(months.items(), key=lambda item: (-item[1], item[0]))
    assert body["busiest_month"] == {"month": month.isoformat(), "count": count}

    log = db_session.scalars(
        select(GroupLog).where(
            GroupLog.group_id == group.id, GroupLog.created_at >= BEGIN, GroupLog.created_at < END
        )
    ).all()
    assert body["ideas_added"] == sum(row.action == "activity.created" for row in log)
    marked_done = Counter(
        row.actor_id
        for row in log
        if row.action == "activity.status_changed" and row.data["to"] == "done"
    )
    assert sum(marked_done.values()) >= len(done)  # the history step records who did it
    top = body["planners"][0]
    assert top["score"] == top["ideas"] + top["events"] + top["polls"] + top["done"]
    assert top["done"] == marked_done[uuid.UUID(top["user"]["id"])]
    assert [c["count"] for c in body["top_categories"]] == sorted(
        (c["count"] for c in body["top_categories"]), reverse=True
    )
    assert body["top_categories"]
    accepted = db_session.scalar(
        select(func.count())
        .select_from(WheelSpin)
        .where(WheelSpin.accepted_at >= BEGIN, WheelSpin.accepted_at < END)
    )
    assert accepted
    assert body["wheel_decisions"] == accepted
    assert body["longest_wait"]["days"] > 30
    assert body["most_wanted"] is not None
