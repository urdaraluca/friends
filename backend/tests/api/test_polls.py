import uuid
from collections.abc import Iterator
from contextlib import contextmanager
from datetime import UTC, datetime, timedelta, timezone
from typing import Any

import pytest
import time_machine
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import event, func, select
from sqlalchemy.orm import Session

from friends_api.features.group_log.models import GroupLog
from friends_api.features.polls.models import Poll, PollOption, PollVote
from tests.factories import (
    DEFAULT_PASSWORD,
    Account,
    add_member,
    create_activity,
    create_group,
    create_invite,
    create_poll,
    join,
    register,
)


def make_admin(client: TestClient, owner: Account, group_id: str, account: Account) -> None:
    response = client.put(
        f"/api/v1/groups/{group_id}/members/{account.id}/role",
        headers=owner.headers,
        json={"role": "admin"},
    )
    assert response.status_code == 200


class Crew:
    """A group with its owner, an admin and three plain members. Alice created (and owns) the
    activity the polls are on."""

    def __init__(self, client: TestClient) -> None:
        self.owner = register(client, display_name="Olga")
        self.group = create_group(client, self.owner)
        self.admin = add_member(client, self.owner, self.group_id)
        make_admin(client, self.owner, self.group_id, self.admin)
        self.alice = add_member(client, self.owner, self.group_id)
        self.bob = add_member(client, self.owner, self.group_id)
        self.carol = add_member(client, self.owner, self.group_id)
        self.activity = create_activity(client, self.alice, self.group_id, title="Movie night")

    @property
    def group_id(self) -> str:
        return str(self.group["id"])

    @property
    def activity_id(self) -> str:
        return str(self.activity["id"])


@pytest.fixture
def crew(client: TestClient) -> Crew:
    return Crew(client)


def poll_url(poll: dict[str, Any], suffix: str = "") -> str:
    return f"/api/v1/polls/{poll['id']}{suffix}"


def polls_url(activity_id: str) -> str:
    return f"/api/v1/activities/{activity_id}/polls"


def options(*labels: str) -> list[dict[str, Any]]:
    return [{"label": label} for label in labels]


def option_id(poll: dict[str, Any], label: str) -> str:
    return next(str(option["id"]) for option in poll["options"] if option["label"] == label)


def by_label(poll: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {option["label"]: option for option in poll["options"]}


def get_poll(client: TestClient, account: Account, poll: dict[str, Any]) -> dict[str, Any]:
    response = client.get(poll_url(poll), headers=account.headers)
    assert response.status_code == 200, response.text
    body: dict[str, Any] = response.json()
    return body


def vote(client: TestClient, account: Account, poll: dict[str, Any], *labels: str) -> Any:
    ids = [option_id(poll, label) for label in labels]
    return client.put(
        poll_url(poll, "/votes/me"), headers=account.headers, json={"option_ids": ids}
    )


def voted(client: TestClient, account: Account, poll: dict[str, Any], *labels: str) -> Any:
    response = vote(client, account, poll, *labels)
    assert response.status_code == 200, response.text
    return response.json()


def post(client: TestClient, account: Account, poll: dict[str, Any], suffix: str) -> Any:
    return client.post(poll_url(poll, suffix), headers=account.headers)


def update_body(poll: dict[str, Any], **changes: Any) -> dict[str, Any]:
    return {"question": poll["question"], "closes_at": poll["closes_at"], **changes}


def iso(moment: datetime) -> str:
    return moment.isoformat().replace("+00:00", "Z")


def in_minutes(minutes: float) -> datetime:
    return datetime.now(UTC) + timedelta(minutes=minutes)


def assert_problem(response: Any, status: int, code: str) -> dict[str, Any]:
    assert response.status_code == status, response.text
    body: dict[str, Any] = response.json()
    assert body["code"] == code, body
    return body


def log_rows(db: Session, action: str) -> list[GroupLog]:
    return list(db.scalars(select(GroupLog).where(GroupLog.action == action).order_by(GroupLog.id)))


# --- create and read ----------------------------------------------------------------------


def test_create_poll_returns_the_whole_poll(client: TestClient, crew: Crew) -> None:
    poll = create_poll(
        client,
        crew.bob,
        crew.activity_id,
        question="  Which movie?  ",
        options=[{"label": " Dune ", "url": "https://example.com/dune"}, {"label": "Up"}],
    )

    assert poll["question"] == "Which movie?"
    assert (poll["group_id"], poll["activity_id"]) == (crew.group_id, crew.activity_id)
    assert poll["allow_multiple"] is False
    assert poll["closes_at"] is poll["closed_at"] is None
    assert poll["is_open"] is True
    assert [(o["label"], o["url"], o["position"]) for o in poll["options"]] == [
        ("Dune", "https://example.com/dune", 0),
        ("Up", None, 1),
    ]
    for option in poll["options"]:
        assert (option["vote_count"], option["voters"]) == (0, [])
        assert option["added_by"]["id"] == crew.bob.id
        assert option["can_delete"] is True  # the creator manages the poll
    assert (poll["my_option_ids"], poll["total_voters"], poll["winning_option_ids"]) == ([], 0, [])
    assert poll["created_by"] == {
        "id": crew.bob.id,
        "display_name": crew.bob.body["user"]["display_name"],
        "avatar_url": None,
    }
    assert poll["can_manage"] is True
    assert poll["created_at"] == poll["updated_at"]


def test_can_manage_follows_the_manager_rule(client: TestClient, crew: Crew) -> None:
    poll = create_poll(client, crew.bob, crew.activity_id)

    views = {
        name: get_poll(client, account, poll)
        for name, account in {
            "creator": crew.bob,
            "activity owner": crew.alice,
            "admin": crew.admin,
            "group owner": crew.owner,
            "plain member": crew.carol,
        }.items()
    }

    assert {name: view["can_manage"] for name, view in views.items()} == {
        "creator": True,
        "activity owner": True,
        "admin": True,
        "group owner": True,
        "plain member": False,
    }
    assert [o["can_delete"] for o in views["plain member"]["options"]] == [False, False]


def test_list_polls_oldest_first(client: TestClient, crew: Crew) -> None:
    first = create_poll(client, crew.bob, crew.activity_id, question="First?")
    second = create_poll(client, crew.carol, crew.activity_id, question="Second?")
    other = create_activity(client, crew.alice, crew.group_id)

    response = client.get(polls_url(crew.activity_id), headers=crew.alice.headers)
    empty = client.get(polls_url(other["id"]), headers=crew.alice.headers)

    assert response.status_code == 200
    assert [poll["id"] for poll in response.json()] == [first["id"], second["id"]]
    assert response.json()[0] == get_poll(client, crew.alice, first)
    assert empty.json() == []


def test_closes_at_is_returned_in_utc(client: TestClient, crew: Crew) -> None:
    closes_at = in_minutes(60 * 24).replace(microsecond=0)
    bucharest = closes_at.astimezone(timezone(timedelta(hours=3))).isoformat()

    poll = create_poll(client, crew.bob, crew.activity_id, closes_at=bucharest)
    updated = client.put(
        poll_url(poll), headers=crew.bob.headers, json=update_body(poll, closes_at=bucharest)
    )

    assert bucharest.endswith("+03:00")
    assert poll["closes_at"] == updated.json()["closes_at"] == iso(closes_at)


@pytest.mark.parametrize(
    ("changes", "field", "error_type"),
    [
        ({"options": options("Only one")}, "options", "too_short"),
        ({"options": options(*(f"Option {i}" for i in range(21)))}, "options", "too_long"),
        ({"options": options("Dune", "Up", "dune")}, "options.2.label", "value_error"),
        ({"options": options("Dune", " ")}, "options.1.label", "string_too_short"),
        ({"options": options("x" * 101, "Up")}, "options.0.label", "string_too_long"),
        (
            {"options": [{"label": "A", "url": "ftp://example.com"}, {"label": "B"}]},
            "options.0.url",
            "value_error",
        ),
        ({"question": ""}, "question", "string_too_short"),
        ({"question": "q" * 201}, "question", "string_too_long"),
        ({"closes_at": "2030-01-01T10:00:00"}, "closes_at", "timezone_aware"),
        ({"closes_at": "2020-01-01T10:00:00Z"}, "closes_at", "datetime_future"),
    ],
)
def test_create_poll_validation(
    client: TestClient, crew: Crew, changes: dict[str, Any], field: str, error_type: str
) -> None:
    body = {"question": "Which one?", "options": options("A", "B"), **changes}

    response = client.post(polls_url(crew.activity_id), headers=crew.bob.headers, json=body)

    problem = assert_problem(response, 422, "validation_error")
    assert [(e["field"], e["type"]) for e in problem["errors"]] == [(field, error_type)]


def test_twenty_options_are_allowed_at_creation(client: TestClient, crew: Crew) -> None:
    poll = create_poll(
        client, crew.bob, crew.activity_id, options=options(*(f"Option {i}" for i in range(20)))
    )

    assert [o["position"] for o in poll["options"]] == list(range(20))


def test_an_activity_has_at_most_ten_polls(client: TestClient, crew: Crew) -> None:
    for i in range(10):
        create_poll(client, crew.bob, crew.activity_id, question=f"Poll {i}?")

    response = client.post(
        polls_url(crew.activity_id),
        headers=crew.bob.headers,
        json={"question": "One more?", "options": options("A", "B")},
    )

    assert_problem(response, 422, "limit_reached")
    other = create_activity(client, crew.alice, crew.group_id)
    create_poll(client, crew.bob, other["id"])  # the limit is per activity


def test_malformed_ids_are_validation_errors(client: TestClient, crew: Crew) -> None:
    response = client.get("/api/v1/polls/not-a-uuid", headers=crew.bob.headers)

    problem = assert_problem(response, 422, "validation_error")
    assert problem["errors"][0]["field"] == "path.poll_id"


def test_a_missing_poll_is_404(client: TestClient, crew: Crew) -> None:
    response = client.get(f"/api/v1/polls/{uuid.uuid7()}", headers=crew.bob.headers)

    assert_problem(response, 404, "not_found")


# --- voting -------------------------------------------------------------------------------


def test_single_choice_a_new_vote_replaces_the_old_one(client: TestClient, crew: Crew) -> None:
    poll = create_poll(client, crew.bob, crew.activity_id, options=options("Dune", "Up"))

    first = voted(client, crew.carol, poll, "Dune")
    second = voted(client, crew.carol, poll, "Up")

    assert first["my_option_ids"] == [option_id(poll, "Dune")]
    assert second["my_option_ids"] == [option_id(poll, "Up")]
    counts = {label: o["vote_count"] for label, o in by_label(second).items()}
    assert counts == {"Dune": 0, "Up": 1}
    assert second["total_voters"] == 1
    assert second["winning_option_ids"] == [option_id(poll, "Up")]
    assert [v["id"] for v in by_label(second)["Up"]["voters"]] == [crew.carol.id]


def test_multiple_choice_counts_every_option(client: TestClient, crew: Crew) -> None:
    poll = create_poll(
        client, crew.bob, crew.activity_id, allow_multiple=True, options=options("A", "B", "C")
    )

    voted(client, crew.carol, poll, "A", "B")
    after = voted(client, crew.alice, poll, "B")

    counts = {label: o["vote_count"] for label, o in by_label(after).items()}
    assert counts == {"A": 1, "B": 2, "C": 0}
    assert after["total_voters"] == 2  # distinct voters, not votes
    assert after["winning_option_ids"] == [option_id(poll, "B")]
    assert [v["id"] for v in by_label(after)["B"]["voters"]] == [crew.carol.id, crew.alice.id]
    assert after["my_option_ids"] == [option_id(poll, "B")]
    assert get_poll(client, crew.carol, poll)["my_option_ids"] == [
        option_id(poll, "A"),
        option_id(poll, "B"),
    ]


def test_ties_give_several_winners(client: TestClient, crew: Crew) -> None:
    poll = create_poll(client, crew.bob, crew.activity_id, options=options("A", "B", "C"))

    voted(client, crew.carol, poll, "A")
    after = voted(client, crew.alice, poll, "C")

    assert after["winning_option_ids"] == [option_id(poll, "A"), option_id(poll, "C")]


def test_an_empty_vote_retracts_and_duplicates_are_ignored(client: TestClient, crew: Crew) -> None:
    poll = create_poll(client, crew.bob, crew.activity_id, options=options("A", "B"))

    duplicated = voted(client, crew.carol, poll, "A", "A")
    retracted = voted(client, crew.carol, poll)

    assert duplicated["my_option_ids"] == [option_id(poll, "A")]
    assert by_label(duplicated)["A"]["vote_count"] == 1
    assert retracted["my_option_ids"] == []
    assert retracted["total_voters"] == 0
    assert retracted["winning_option_ids"] == []


def test_more_than_one_choice_on_a_single_choice_poll(client: TestClient, crew: Crew) -> None:
    poll = create_poll(client, crew.bob, crew.activity_id, options=options("A", "B"))

    response = vote(client, crew.carol, poll, "A", "B")

    problem = assert_problem(response, 422, "too_many_choices")
    assert problem["errors"][0]["field"] == "option_ids"


def test_an_option_of_another_poll_is_an_invalid_reference(client: TestClient, crew: Crew) -> None:
    poll = create_poll(client, crew.bob, crew.activity_id, allow_multiple=True)
    other = create_poll(client, crew.bob, crew.activity_id)
    ids = [option_id(poll, "Yes"), option_id(other, "Yes"), str(uuid.uuid7())]

    response = client.put(
        poll_url(poll, "/votes/me"), headers=crew.carol.headers, json={"option_ids": ids}
    )

    problem = assert_problem(response, 422, "invalid_reference")
    assert [e["field"] for e in problem["errors"]] == ["option_ids.1", "option_ids.2"]
    assert get_poll(client, crew.carol, poll)["my_option_ids"] == []


def test_at_most_twenty_option_ids(client: TestClient, crew: Crew) -> None:
    poll = create_poll(client, crew.bob, crew.activity_id, allow_multiple=True)

    response = client.put(
        poll_url(poll, "/votes/me"),
        headers=crew.carol.headers,
        json={"option_ids": [option_id(poll, "Yes")] * 21},
    )

    problem = assert_problem(response, 422, "validation_error")
    assert problem["errors"][0]["field"] == "option_ids"


# --- closing and reopening ----------------------------------------------------------------


def test_voting_after_a_manual_close_is_rejected(client: TestClient, crew: Crew) -> None:
    poll = create_poll(client, crew.bob, crew.activity_id)
    voted(client, crew.carol, poll, "Yes")

    closed = post(client, crew.bob, poll, "/close")

    assert closed.status_code == 200
    assert closed.json()["is_open"] is False
    assert closed.json()["closed_at"] is not None
    assert_problem(vote(client, crew.alice, poll, "No"), 409, "poll_closed")
    assert_problem(vote(client, crew.carol, poll), 409, "poll_closed")  # nor retract
    add = client.post(poll_url(poll, "/options"), headers=crew.alice.headers, json={"label": "?"})
    assert_problem(add, 409, "poll_closed")
    assert get_poll(client, crew.carol, poll)["my_option_ids"] == [option_id(poll, "Yes")]


def test_closing_is_idempotent(client: TestClient, crew: Crew, db_session: Session) -> None:
    poll = create_poll(client, crew.bob, crew.activity_id)

    first = post(client, crew.bob, poll, "/close").json()
    second = post(client, crew.bob, poll, "/close")

    assert second.status_code == 200
    assert second.json()["closed_at"] == first["closed_at"]
    assert len(log_rows(db_session, "poll.closed")) == 1


def test_reopening_clears_closed_at(client: TestClient, crew: Crew) -> None:
    closes_at = iso(in_minutes(60).replace(microsecond=0))
    poll = create_poll(client, crew.bob, crew.activity_id, closes_at=closes_at)
    post(client, crew.bob, poll, "/close")

    reopened = post(client, crew.bob, poll, "/reopen")

    assert reopened.status_code == 200
    assert (reopened.json()["is_open"], reopened.json()["closed_at"]) == (True, None)
    assert reopened.json()["closes_at"] == closes_at  # still in the future: kept
    voted(client, crew.carol, poll, "Yes")


def test_a_past_closes_at_counts_as_closed_and_reopening_clears_it(
    client: TestClient, crew: Crew, db_session: Session
) -> None:
    closes_at = in_minutes(5)
    poll = create_poll(client, crew.bob, crew.activity_id, closes_at=iso(closes_at))

    with time_machine.travel(closes_at + timedelta(minutes=1), tick=False):
        seen = get_poll(client, crew.carol, poll)
        rejected = vote(client, crew.carol, poll, "Yes")
        reopened = post(client, crew.bob, poll, "/reopen")
        accepted = vote(client, crew.carol, poll, "Yes")

    assert (seen["is_open"], seen["closed_at"]) == (False, None)  # GET never writes
    assert_problem(rejected, 409, "poll_closed")
    assert reopened.status_code == 200
    assert reopened.json()["closes_at"] is None
    assert reopened.json()["is_open"] is True
    assert accepted.status_code == 200
    assert len(log_rows(db_session, "poll.reopened")) == 1


def test_reopening_an_open_poll_changes_nothing(
    client: TestClient, crew: Crew, db_session: Session
) -> None:
    poll = create_poll(client, crew.bob, crew.activity_id)

    response = post(client, crew.bob, poll, "/reopen")

    assert response.status_code == 200
    assert response.json() == get_poll(client, crew.bob, poll)
    assert log_rows(db_session, "poll.reopened") == []


def test_the_activity_owner_can_close_a_poll_a_plain_member_cant(
    client: TestClient, crew: Crew
) -> None:
    poll = create_poll(client, crew.bob, crew.activity_id)  # alice owns the activity

    denied = post(client, crew.carol, poll, "/close")
    closed = post(client, crew.alice, poll, "/close")

    assert_problem(denied, 403, "forbidden")
    assert closed.status_code == 200
    assert closed.json()["is_open"] is False
    assert_problem(post(client, crew.carol, poll, "/reopen"), 403, "forbidden")
    assert post(client, crew.admin, poll, "/reopen").json()["is_open"] is True


def test_a_new_activity_owner_manages_its_polls(client: TestClient, crew: Crew) -> None:
    poll = create_poll(client, crew.bob, crew.activity_id)
    activity = client.get(f"/api/v1/activities/{crew.activity_id}", headers=crew.alice.headers)
    body = {
        **{k: activity.json()[k] for k in ("title", "links", "attributes", "version")},
        "owner_id": crew.carol.id,
    }
    handed_over = client.put(
        f"/api/v1/activities/{crew.activity_id}", headers=crew.alice.headers, json=body
    )
    assert handed_over.status_code == 200, handed_over.text

    assert get_poll(client, crew.carol, poll)["can_manage"] is True
    assert get_poll(client, crew.alice, poll)["can_manage"] is False
    assert post(client, crew.carol, poll, "/close").status_code == 200


# --- editing and deleting -----------------------------------------------------------------


def test_update_poll(client: TestClient, crew: Crew, db_session: Session) -> None:
    poll = create_poll(client, crew.bob, crew.activity_id, question="Which movie?")
    closes_at = iso(in_minutes(90).replace(microsecond=0))

    response = client.put(
        poll_url(poll),
        headers=crew.alice.headers,
        json=update_body(poll, question="Which film?", closes_at=closes_at),
    )
    unchanged = client.put(
        poll_url(poll), headers=crew.alice.headers, json=update_body(response.json())
    )

    assert response.status_code == 200
    assert (response.json()["question"], response.json()["closes_at"]) == (
        "Which film?",
        closes_at,
    )
    assert response.json()["allow_multiple"] is False
    assert unchanged.status_code == 200
    rows = log_rows(db_session, "poll.updated")
    assert len(rows) == 1  # an unchanged PUT isn't logged
    assert rows[0].data == {"activity_id": crew.activity_id, "question": "Which film?"}


def test_update_poll_is_for_managers(client: TestClient, crew: Crew) -> None:
    poll = create_poll(client, crew.bob, crew.activity_id)

    response = client.put(
        poll_url(poll), headers=crew.carol.headers, json=update_body(poll, question="Mine?")
    )

    assert_problem(response, 403, "forbidden")


def test_update_poll_may_resend_a_past_closes_at_unchanged(client: TestClient, crew: Crew) -> None:
    closes_at = in_minutes(5)
    poll = create_poll(client, crew.bob, crew.activity_id, closes_at=iso(closes_at))

    with time_machine.travel(closes_at + timedelta(minutes=1), tick=False):
        kept = client.put(
            poll_url(poll), headers=crew.bob.headers, json=update_body(poll, question="Renamed?")
        )
        moved = client.put(
            poll_url(poll),
            headers=crew.bob.headers,
            json=update_body(poll, closes_at=iso(closes_at + timedelta(seconds=30))),
        )
        cleared = client.put(
            poll_url(poll), headers=crew.bob.headers, json=update_body(poll, closes_at=None)
        )

    assert kept.status_code == 200, kept.text
    assert (kept.json()["question"], kept.json()["is_open"]) == ("Renamed?", False)
    problem = assert_problem(moved, 422, "validation_error")
    assert problem["errors"][0]["field"] == "closes_at"
    assert cleared.status_code == 200
    assert (cleared.json()["closes_at"], cleared.json()["is_open"]) == (None, True)


def test_delete_poll_removes_options_and_votes(
    client: TestClient, crew: Crew, db_session: Session
) -> None:
    poll = create_poll(client, crew.bob, crew.activity_id)
    voted(client, crew.carol, poll, "Yes")

    denied = client.delete(poll_url(poll), headers=crew.carol.headers)
    response = client.delete(poll_url(poll), headers=crew.alice.headers)

    assert_problem(denied, 403, "forbidden")
    assert response.status_code == 204
    assert response.content == b""
    assert_problem(client.get(poll_url(poll), headers=crew.bob.headers), 404, "not_found")
    for table in (Poll, PollOption, PollVote):
        assert db_session.scalar(select(func.count()).select_from(table)) == 0
    (row,) = log_rows(db_session, "poll.deleted")
    assert row.data == {"activity_id": crew.activity_id, "question": poll["question"]}
    assert (row.subject_type, str(row.subject_id), str(row.actor_id)) == (
        "poll",
        poll["id"],
        crew.alice.id,
    )


def test_deleting_the_activity_deletes_its_polls(
    client: TestClient, crew: Crew, db_session: Session
) -> None:
    poll = create_poll(client, crew.bob, crew.activity_id)
    voted(client, crew.carol, poll, "Yes")

    response = client.delete(f"/api/v1/activities/{crew.activity_id}", headers=crew.alice.headers)

    assert response.status_code == 204
    assert_problem(client.get(poll_url(poll), headers=crew.bob.headers), 404, "not_found")
    for table in (Poll, PollOption, PollVote):
        assert db_session.scalar(select(func.count()).select_from(table)) == 0


# --- options ------------------------------------------------------------------------------


def test_any_member_can_add_an_option_and_it_goes_last(client: TestClient, crew: Crew) -> None:
    poll = create_poll(client, crew.bob, crew.activity_id, options=options("A", "B", "C"))
    trimmed = client.delete(
        poll_url(poll, f"/options/{option_id(poll, 'B')}"), headers=crew.bob.headers
    )
    assert trimmed.status_code == 200

    response = client.post(
        poll_url(poll, "/options"),
        headers=crew.carol.headers,
        json={"label": "  D  ", "url": "https://example.com/d"},
    )

    assert response.status_code == 201
    added = by_label(response.json())["D"]
    assert [o["label"] for o in response.json()["options"]] == ["A", "C", "D"]
    assert (added["position"], added["url"]) == (3, "https://example.com/d")
    assert added["added_by"]["id"] == crew.carol.id
    assert added["can_delete"] is True  # its adder, while nobody voted for it
    assert by_label(response.json())["A"]["can_delete"] is False
    assert response.json()["can_manage"] is False


def test_an_option_label_must_be_new_on_the_poll(client: TestClient, crew: Crew) -> None:
    poll = create_poll(client, crew.bob, crew.activity_id, options=options("Dune", "Up"))

    response = client.post(
        poll_url(poll, "/options"), headers=crew.carol.headers, json={"label": "DUNE"}
    )

    assert_problem(response, 409, "name_taken")


def test_label_uniqueness_folds_ascii_only_like_nocase(client: TestClient, crew: Crew) -> None:
    """Contract 1.10: NOCASE folds ASCII letters only, so these are different labels."""
    poll = create_poll(client, crew.bob, crew.activity_id, options=options("Maße", "Café"))

    added = client.post(
        poll_url(poll, "/options"), headers=crew.carol.headers, json={"label": "Masse"}
    )
    created = client.post(
        polls_url(crew.activity_id),
        headers=crew.bob.headers,
        json={"question": "Where?", "options": options("Straße", "Strasse", "CAFÉ", "café")},
    )

    assert added.status_code == 201, added.text
    assert created.status_code == 201, created.text


def test_a_poll_has_at_most_twenty_options(client: TestClient, crew: Crew) -> None:
    poll = create_poll(
        client, crew.bob, crew.activity_id, options=options(*(f"Option {i}" for i in range(19)))
    )
    added = client.post(poll_url(poll, "/options"), headers=crew.carol.headers, json={"label": "X"})

    response = client.post(
        poll_url(poll, "/options"), headers=crew.carol.headers, json={"label": "Y"}
    )

    assert added.status_code == 201
    assert len(added.json()["options"]) == 20
    assert_problem(response, 422, "limit_reached")


def test_deleting_an_option_removes_its_votes(
    client: TestClient, crew: Crew, db_session: Session
) -> None:
    poll = create_poll(
        client, crew.bob, crew.activity_id, allow_multiple=True, options=options("A", "B", "C")
    )
    voted(client, crew.carol, poll, "A", "B")
    voted(client, crew.alice, poll, "A")

    response = client.delete(
        poll_url(poll, f"/options/{option_id(poll, 'A')}"), headers=crew.bob.headers
    )

    assert response.status_code == 200
    after = response.json()
    assert [o["label"] for o in after["options"]] == ["B", "C"]
    assert after["total_voters"] == 1
    assert after["winning_option_ids"] == [option_id(poll, "B")]
    assert get_poll(client, crew.alice, poll)["my_option_ids"] == []
    assert get_poll(client, crew.carol, poll)["my_option_ids"] == [option_id(poll, "B")]
    remaining = db_session.scalars(select(PollVote.option_id)).all()
    assert [str(option) for option in remaining] == [option_id(poll, "B")]


def test_the_adder_can_delete_an_option_only_until_it_has_votes(
    client: TestClient, crew: Crew
) -> None:
    poll = create_poll(client, crew.bob, crew.activity_id, options=options("A", "B"))
    for label in ("C", "D"):
        client.post(poll_url(poll, "/options"), headers=crew.carol.headers, json={"label": label})
    poll = get_poll(client, crew.carol, poll)

    free = client.delete(
        poll_url(poll, f"/options/{option_id(poll, 'C')}"), headers=crew.carol.headers
    )
    voted(client, crew.alice, poll, "D")
    view = get_poll(client, crew.carol, poll)
    taken = client.delete(
        poll_url(poll, f"/options/{option_id(poll, 'D')}"), headers=crew.carol.headers
    )
    by_manager = client.delete(
        poll_url(poll, f"/options/{option_id(poll, 'D')}"), headers=crew.bob.headers
    )

    assert free.status_code == 200
    assert by_label(view)["D"]["can_delete"] is False
    assert_problem(taken, 403, "forbidden")
    assert by_manager.status_code == 200
    assert [o["label"] for o in by_manager.json()["options"]] == ["A", "B"]


def test_a_poll_keeps_at_least_two_options(client: TestClient, crew: Crew) -> None:
    poll = create_poll(client, crew.bob, crew.activity_id, options=options("A", "B"))

    response = client.delete(
        poll_url(poll, f"/options/{option_id(poll, 'A')}"), headers=crew.bob.headers
    )

    assert_problem(response, 422, "limit_reached")
    assert len(get_poll(client, crew.bob, poll)["options"]) == 2


def test_an_option_of_another_poll_is_not_found(client: TestClient, crew: Crew) -> None:
    poll = create_poll(client, crew.bob, crew.activity_id, options=options("A", "B", "C"))
    other = create_poll(client, crew.bob, crew.activity_id)

    response = client.delete(
        poll_url(poll, f"/options/{option_id(other, 'Yes')}"), headers=crew.bob.headers
    )

    assert_problem(response, 404, "not_found")


# --- the log ------------------------------------------------------------------------------


def test_every_change_is_logged_with_its_data(
    client: TestClient, crew: Crew, db_session: Session
) -> None:
    poll = create_poll(client, crew.bob, crew.activity_id, options=options("A", "B"))
    added = client.post(poll_url(poll, "/options"), headers=crew.carol.headers, json={"label": "C"})
    c_id = option_id(added.json(), "C")
    voted(client, crew.carol, poll, "A")
    voted(client, crew.carol, poll, "A")  # unchanged: not logged
    voted(client, crew.carol, poll)
    client.delete(poll_url(poll, f"/options/{c_id}"), headers=crew.carol.headers)
    post(client, crew.bob, poll, "/close")
    post(client, crew.bob, poll, "/reopen")

    rows = db_session.scalars(
        select(GroupLog).where(GroupLog.subject_type == "poll").order_by(GroupLog.id)
    ).all()

    about = {"activity_id": crew.activity_id, "question": poll["question"]}
    assert [(row.action, str(row.actor_id), row.data) for row in rows] == [
        ("poll.created", crew.bob.id, about),
        ("poll.option_added", crew.carol.id, {"option_id": c_id, "label": "C"}),
        ("poll.voted", crew.carol.id, {"option_ids": [option_id(poll, "A")]}),
        ("poll.voted", crew.carol.id, {"option_ids": []}),
        ("poll.option_deleted", crew.carol.id, {"option_id": c_id, "label": "C"}),
        ("poll.closed", crew.bob.id, about),
        ("poll.reopened", crew.bob.id, about),
    ]
    assert {str(row.subject_id) for row in rows} == {poll["id"]}
    assert {str(row.group_id) for row in rows} == {crew.group_id}


# --- activity counters --------------------------------------------------------------------


def counters(activity: dict[str, Any]) -> tuple[int, int, int]:
    return (
        activity["poll_count"],
        activity["open_poll_count"],
        activity["my_unvoted_poll_count"],
    )


def summary(client: TestClient, account: Account, crew: Crew, activity_id: str) -> dict[str, Any]:
    page = client.get(f"/api/v1/groups/{crew.group_id}/activities", headers=account.headers)
    assert page.status_code == 200
    return next(item for item in page.json()["items"] if item["id"] == activity_id)


def detail(client: TestClient, account: Account, activity_id: str) -> dict[str, Any]:
    response = client.get(f"/api/v1/activities/{activity_id}", headers=account.headers)
    assert response.status_code == 200
    body: dict[str, Any] = response.json()
    return body


def test_activity_counters_and_the_vote_badge(client: TestClient, crew: Crew) -> None:
    open_poll = create_poll(client, crew.bob, crew.activity_id, question="Open?")
    create_poll(client, crew.bob, crew.activity_id, question="Also open?")
    closed = create_poll(client, crew.bob, crew.activity_id, question="Closed?")
    post(client, crew.bob, closed, "/close")
    voted(client, crew.alice, open_poll, "Yes")
    untouched = create_activity(client, crew.alice, crew.group_id)

    assert counters(summary(client, crew.carol, crew, crew.activity_id)) == (3, 2, 2)
    assert counters(summary(client, crew.alice, crew, crew.activity_id)) == (3, 2, 1)
    assert counters(detail(client, crew.alice, crew.activity_id)) == (3, 2, 1)
    assert counters(summary(client, crew.alice, crew, untouched["id"])) == (0, 0, 0)

    for poll in client.get(polls_url(crew.activity_id), headers=crew.carol.headers).json():
        if poll["is_open"]:
            voted(client, crew.carol, poll, "No")

    assert counters(summary(client, crew.carol, crew, crew.activity_id)) == (3, 2, 0)
    assert counters(detail(client, crew.carol, crew.activity_id)) == (3, 2, 0)


def test_counters_treat_a_past_closes_at_as_closed(client: TestClient, crew: Crew) -> None:
    closes_at = in_minutes(5)
    create_poll(client, crew.bob, crew.activity_id, closes_at=iso(closes_at))

    before = counters(detail(client, crew.carol, crew.activity_id))
    with time_machine.travel(closes_at + timedelta(minutes=1), tick=False):
        after = counters(detail(client, crew.carol, crew.activity_id))

    assert (before, after) == ((1, 1, 1), (1, 0, 0))


@contextmanager
def count_selects(app: FastAPI) -> Iterator[list[str]]:
    statements: list[str] = []

    def record(_conn: Any, _cursor: Any, statement: str, *_args: Any) -> None:
        if statement.lstrip().upper().startswith("SELECT"):
            statements.append(statement)

    engine = app.state.engine
    event.listen(engine, "before_cursor_execute", record)
    try:
        yield statements
    finally:
        event.remove(engine, "before_cursor_execute", record)


def test_reading_polls_uses_a_fixed_number_of_queries(
    app: FastAPI, client: TestClient, crew: Crew
) -> None:
    create_poll(client, crew.bob, crew.activity_id)
    with count_selects(app) as one:
        client.get(polls_url(crew.activity_id), headers=crew.carol.headers)

    for i in range(4):
        poll = create_poll(
            client, crew.bob, crew.activity_id, allow_multiple=True, options=options("A", "B", "C")
        )
        voted(client, crew.carol, poll, "A", "B")
        voted(client, crew.alice, poll, "C")
        client.post(poll_url(poll, "/options"), headers=crew.alice.headers, json={"label": f"{i}"})
    with count_selects(app) as many:
        client.get(polls_url(crew.activity_id), headers=crew.carol.headers)

    assert len(one) == len(many), many


def test_listing_activities_with_polls_uses_a_fixed_number_of_queries(
    app: FastAPI, client: TestClient, crew: Crew
) -> None:
    with count_selects(app) as without:
        client.get(f"/api/v1/groups/{crew.group_id}/activities", headers=crew.carol.headers)

    for i in range(5):
        activity = create_activity(client, crew.alice, crew.group_id, title=f"Other {i}")
        poll = create_poll(client, crew.bob, activity["id"])
        voted(client, crew.carol, poll, "Yes")
    with count_selects(app) as with_polls:
        client.get(f"/api/v1/groups/{crew.group_id}/activities", headers=crew.carol.headers)

    assert len(without) == len(with_polls), with_polls


# --- membership end (contract section 7.5) ------------------------------------------------


class Voter:
    """Carol voted on a poll in the crew group and on one in a second group ("Elsewhere")."""

    def __init__(self, client: TestClient, crew: Crew) -> None:
        self.here = create_poll(client, crew.bob, crew.activity_id, allow_multiple=True)
        voted(client, crew.carol, self.here, "Yes", "No")
        voted(client, crew.alice, self.here, "Yes")
        elsewhere = create_group(client, crew.alice, name="Elsewhere")
        join(client, crew.carol, create_invite(client, crew.alice, elsewhere["id"])["code"])
        activity = create_activity(client, crew.alice, elsewhere["id"])
        self.there = create_poll(client, crew.alice, activity["id"])
        voted(client, crew.carol, self.there, "No")


def voter_ids(client: TestClient, account: Account, poll: dict[str, Any]) -> set[str]:
    return {v["id"] for o in get_poll(client, account, poll)["options"] for v in o["voters"]}


def test_leaving_the_group_removes_that_members_votes_there_only(
    client: TestClient, crew: Crew
) -> None:
    voter = Voter(client, crew)

    response = client.delete(
        f"/api/v1/groups/{crew.group_id}/members/{crew.carol.id}", headers=crew.carol.headers
    )

    assert response.status_code == 204
    here = get_poll(client, crew.alice, voter.here)
    assert voter_ids(client, crew.alice, voter.here) == {crew.alice.id}
    assert (here["total_voters"], here["winning_option_ids"]) == (1, [option_id(here, "Yes")])
    assert voter_ids(client, crew.alice, voter.there) == {crew.carol.id}


def test_being_removed_removes_that_members_votes(client: TestClient, crew: Crew) -> None:
    voter = Voter(client, crew)

    response = client.delete(
        f"/api/v1/groups/{crew.group_id}/members/{crew.carol.id}", headers=crew.admin.headers
    )

    assert response.status_code == 204
    assert voter_ids(client, crew.alice, voter.here) == {crew.alice.id}
    assert voter_ids(client, crew.alice, voter.there) == {crew.carol.id}


def test_account_deletion_removes_votes_in_every_group(client: TestClient, crew: Crew) -> None:
    voter = Voter(client, crew)

    response = client.post(
        "/api/v1/me/deletion", headers=crew.carol.headers, json={"password": DEFAULT_PASSWORD}
    )

    assert response.status_code == 204
    assert voter_ids(client, crew.alice, voter.here) == {crew.alice.id}
    assert voter_ids(client, crew.alice, voter.there) == set()


def test_polls_of_a_deleted_creator_stay(client: TestClient, crew: Crew) -> None:
    poll = create_poll(client, crew.carol, crew.activity_id)

    client.post(
        "/api/v1/me/deletion", headers=crew.carol.headers, json={"password": DEFAULT_PASSWORD}
    )

    after = get_poll(client, crew.alice, poll)
    assert after["created_by"]["display_name"] == "Deleted user"
    assert after["options"][0]["added_by"]["display_name"] == "Deleted user"
