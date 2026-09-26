from collections import Counter

from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from friends_api import cli
from friends_api.core.config import Settings
from friends_api.demo.context import DEMO_EMAILS, DEMO_PASSWORD
from friends_api.features.activities.models import Activity
from friends_api.features.group_log.models import GroupLog
from friends_api.features.polls.models import Poll, PollOption, PollVote
from friends_api.main import create_app


def test_seed_demo_creates_polls_with_votes(settings: Settings, db_session: Session) -> None:
    assert cli.main(["seed-demo"], settings) == 0

    polls = {poll.question: poll for poll in db_session.scalars(select(Poll))}
    assert set(polls) == {"Which movie?", "Snacks?", "When should we go?", "Which evening?"}
    movie_night = db_session.get(Activity, polls["Which movie?"].activity_id)
    assert movie_night is not None
    assert movie_night.title == "Friday movie night"
    assert polls["Snacks?"].allow_multiple
    assert polls["Which evening?"].closed_at is not None
    options = db_session.scalars(select(PollOption)).all()
    assert len({option.added_by_id for option in options}) >= 3
    assert any(option.url for option in options)
    votes = db_session.scalars(select(PollVote)).all()
    per_voter = Counter((vote.poll_id, vote.user_id) for vote in votes)
    assert max(per_voter.values()) >= 2  # multiple choice
    assert {vote.poll_id for vote in votes} == {poll.id for poll in polls.values()}
    logged = Counter(
        db_session.scalars(select(GroupLog.action).where(GroupLog.subject_type == "poll"))
    )
    assert logged["poll.created"] == 4
    assert logged["poll.voted"] == len(per_voter)
    assert logged["poll.closed"] == 1

    with TestClient(create_app(settings)) as client:
        login = client.post(
            "/api/v1/auth/login", json={"email": DEMO_EMAILS[2], "password": DEMO_PASSWORD}
        )
        headers = {"Authorization": f"Bearer {login.json()['tokens']['access_token']}"}
        activity = client.get(f"/api/v1/activities/{movie_night.id}", headers=headers).json()
        listed = client.get(f"/api/v1/activities/{movie_night.id}/polls", headers=headers).json()
    assert activity["poll_count"] == 2
    assert activity["my_unvoted_poll_count"] == 1  # the member hasn't picked a movie yet
    assert [poll["question"] for poll in listed] == ["Which movie?", "Snacks?"]
    assert listed[1]["total_voters"] == 3
