import uuid

from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from friends_api import cli
from friends_api.core.config import Settings
from friends_api.demo.context import DEMO_EMAILS, DEMO_PASSWORD
from friends_api.features.activities.models import Activity, ActivityStatus
from friends_api.features.group_log.models import GroupLog
from friends_api.features.wheel.models import WheelSpin
from friends_api.main import create_app


def test_seed_demo_spins_the_wheel_a_few_times(settings: Settings, db_session: Session) -> None:
    assert cli.main(["seed-demo"], settings) == 0

    spins = db_session.scalars(select(WheelSpin).order_by(WheelSpin.created_at)).all()
    assert 3 <= len(spins) <= 8
    accepted = [spin for spin in spins if spin.accepted_at is not None]
    assert 0 < len(accepted) < len(spins)
    assert any(len(spin.candidates) == 50 for spin in spins)  # a pool sampled down to 50
    activities = {a.id: a for a in db_session.scalars(select(Activity))}
    for spin in spins:
        assert 2 <= len(spin.candidates) <= 50
        result = spin.candidates[spin.result_index]
        assert spin.result_activity_id == uuid.UUID(result["id"])
        # Every slice existed when the wheel was spun.
        assert all(
            activities[uuid.UUID(c["id"])].created_at < spin.created_at for c in spin.candidates
        )
    for spin in accepted:
        assert spin.accepted_by_id is not None
        assert spin.accepted_at is not None
        assert spin.accepted_at > spin.created_at
        assert spin.result_activity_id is not None
        assert activities[spin.result_activity_id].status is not ActivityStatus.IDEA
    moved = db_session.scalars(
        select(GroupLog.subject_id).where(
            GroupLog.action == "activity.status_changed",
            GroupLog.data["via"].as_string() == "wheel",
        )
    ).all()
    assert moved  # at least one accepted idea moved to planning
    for activity_id in moved:
        assert activity_id is not None
        activity = activities[activity_id]
        assert activity.status is ActivityStatus.PLANNING
        assert activity.status_changed_at in {spin.accepted_at for spin in accepted}

    with TestClient(create_app(settings)) as client:
        login = client.post(
            "/api/v1/auth/login", json={"email": DEMO_EMAILS[2], "password": DEMO_PASSWORD}
        )
        headers = {"Authorization": f"Bearer {login.json()['tokens']['access_token']}"}
        history = client.get(f"/api/v1/groups/{spins[0].group_id}/wheel/spins", headers=headers)
    assert history.status_code == 200
    assert [item["id"] for item in history.json()["items"]] == [
        str(spin.id) for spin in reversed(spins)
    ]
