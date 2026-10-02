"""The book archive (contract section 17) and group kinds (section 17.1)."""

import uuid
from typing import Any

from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from friends_api.features.group_log.models import GroupLog
from tests.factories import Account, add_member, create_book, create_group, register


class Club:
    """A book club: Olga owns the group, Ana owns a book, Bob and Cleo want to borrow it."""

    def __init__(self, client: TestClient) -> None:
        self.client = client
        self.owner = register(client, display_name="Olga")
        self.group = create_group(client, self.owner, kind="book_club")
        self.ana = add_member(client, self.owner, self.group_id)
        self.bob = add_member(client, self.owner, self.group_id)
        self.cleo = add_member(client, self.owner, self.group_id)
        self.book = create_book(client, self.ana, self.group_id, title="Dune", description="Spice.")

    @property
    def group_id(self) -> str:
        return str(self.group["id"])

    @property
    def book_id(self) -> str:
        return str(self.book["id"])

    def get(self, account: Account) -> dict[str, Any]:
        response = self.client.get(f"/api/v1/books/{self.book_id}", headers=account.headers)
        assert response.status_code == 200, response.text
        body: dict[str, Any] = response.json()
        return body

    def queue(self, account: Account, method: str = "PUT") -> Any:
        return self.client.request(
            method, f"/api/v1/books/{self.book_id}/queue", headers=account.headers
        )

    def hand_over(self, account: Account, to: Account | str | None) -> Any:
        to_id = to.id if isinstance(to, Account) else to
        return self.client.post(
            f"/api/v1/books/{self.book_id}/handover",
            headers=account.headers,
            json={"to_user_id": to_id},
        )


def _queue_ids(book: dict[str, Any]) -> list[str]:
    return [entry["user"]["id"] for entry in book["queue"]]


def _logged(db: Session, group_id: str) -> list[tuple[str, dict[str, Any]]]:
    rows = db.execute(
        select(GroupLog.action, GroupLog.data)
        .where(
            GroupLog.group_id == uuid.UUID(group_id),
            GroupLog.subject_type == "book",
        )
        .order_by(GroupLog.created_at, GroupLog.id)
    ).all()
    return [(action, data) for action, data in rows]


# --- group kinds --------------------------------------------------------------------------


def test_a_group_is_general_unless_told_otherwise(client: TestClient) -> None:
    owner = register(client)
    group = create_group(client, owner)
    assert group["kind"] == "general"

    listed = client.get("/api/v1/groups", headers=owner.headers).json()
    assert listed[0]["kind"] == "general"


def test_the_kind_can_change_and_null_keeps_it(client: TestClient) -> None:
    owner = register(client)
    group = create_group(client, owner, kind="movie_night")
    body = {"name": "G", "currency": "EUR", "timezone": "UTC", "members_can_invite": True}

    kept = client.put(f"/api/v1/groups/{group['id']}", headers=owner.headers, json=body)
    changed = client.put(
        f"/api/v1/groups/{group['id']}", headers=owner.headers, json={**body, "kind": "book_club"}
    )

    assert kept.json()["kind"] == "movie_night"
    assert changed.json()["kind"] == "book_club"
    unknown = client.put(
        f"/api/v1/groups/{group['id']}", headers=owner.headers, json={**body, "kind": "chess"}
    )
    assert unknown.status_code == 422


# --- the archive --------------------------------------------------------------------------


def test_adding_a_book(client: TestClient, db_session: Session) -> None:
    club = Club(client)

    book = club.book
    assert (book["title"], book["author"], book["description"]) == ("Dune", "Someone", "Spice.")
    assert book["owner"]["id"] == club.ana.id
    assert book["holder"] is None
    assert book["held_since"] is None
    assert book["queue"] == []
    assert book["in_my_queue"] is False
    assert book["can_edit"] is book["can_hand_over"] is True
    assert _logged(db_session, club.group_id) == [("book.added", {"title": "Dune"})]


def test_others_see_what_they_may_do(client: TestClient) -> None:
    club = Club(client)

    assert (club.get(club.bob)["can_edit"], club.get(club.bob)["can_hand_over"]) == (False, False)
    assert (club.get(club.owner)["can_edit"], club.get(club.owner)["can_hand_over"]) == (
        True,
        True,
    )


def test_books_are_listed_by_title_case_insensitively(client: TestClient) -> None:
    club = Club(client)
    create_book(client, club.bob, club.group_id, title="anna Karenina", author=None)
    create_book(client, club.cleo, club.group_id, title="Zorba the Greek")

    listed = client.get(f"/api/v1/groups/{club.group_id}/books", headers=club.bob.headers)

    assert listed.status_code == 200
    assert [b["title"] for b in listed.json()] == ["anna Karenina", "Dune", "Zorba the Greek"]
    assert listed.json()[0]["author"] is None


def test_a_book_needs_a_title(client: TestClient) -> None:
    club = Club(client)

    for title in ("  ", "x" * 201):
        response = client.post(
            f"/api/v1/groups/{club.group_id}/books",
            headers=club.bob.headers,
            json={"title": title},
        )
        assert response.status_code == 422
        assert response.json()["errors"][0]["field"] == "title"


def test_the_owner_edits_and_deletes(client: TestClient, db_session: Session) -> None:
    club = Club(client)

    edited = client.put(
        f"/api/v1/books/{club.book_id}",
        headers=club.ana.headers,
        json={"title": "Dune", "author": "Frank Herbert", "description": ""},
    )
    assert edited.status_code == 200
    assert (edited.json()["author"], edited.json()["description"]) == ("Frank Herbert", None)

    deleted = client.delete(f"/api/v1/books/{club.book_id}", headers=club.ana.headers)
    assert deleted.status_code == 204
    assert client.get(f"/api/v1/books/{club.book_id}", headers=club.ana.headers).status_code == 404
    assert [action for action, _ in _logged(db_session, club.group_id)] == [
        "book.added",
        "book.updated",
        "book.deleted",
    ]
    assert _logged(db_session, club.group_id)[1][1]["fields"] == ["author", "description"]


def test_an_admin_may_edit_anyones_book(client: TestClient) -> None:
    club = Club(client)

    response = client.put(
        f"/api/v1/books/{club.book_id}",
        headers=club.owner.headers,
        json={"title": "Dune Messiah"},
    )

    assert response.status_code == 200
    assert response.json()["title"] == "Dune Messiah"


# --- the queue ----------------------------------------------------------------------------


def test_members_queue_first_come_first_served(client: TestClient) -> None:
    club = Club(client)

    assert club.queue(club.cleo).status_code == 200
    joined = club.queue(club.bob)
    again = club.queue(club.cleo)  # idempotent: keeps her place

    assert joined.status_code == again.status_code == 200
    assert _queue_ids(again.json()) == [club.cleo.id, club.bob.id]
    assert again.json()["in_my_queue"] is True
    assert club.get(club.ana)["in_my_queue"] is False

    left = club.queue(club.cleo, "DELETE")
    assert _queue_ids(left.json()) == [club.bob.id]
    assert club.queue(club.cleo, "DELETE").status_code == 200  # idempotent


def test_the_owner_and_the_holder_cant_queue(client: TestClient) -> None:
    club = Club(client)
    club.hand_over(club.ana, club.bob)

    own = club.queue(club.ana)
    holding = club.queue(club.bob)

    assert (own.status_code, own.json()["code"]) == (409, "own_book")
    assert (holding.status_code, holding.json()["code"]) == (409, "already_holding")


# --- handing over -------------------------------------------------------------------------


def test_lending_to_the_next_in_line_and_back(client: TestClient, db_session: Session) -> None:
    club = Club(client)
    club.queue(club.bob)
    club.queue(club.cleo)

    lent = club.hand_over(club.ana, club.bob)
    assert lent.status_code == 200
    assert lent.json()["holder"]["id"] == club.bob.id
    assert lent.json()["held_since"] is not None
    assert _queue_ids(lent.json()) == [club.cleo.id]  # Bob left the queue
    # Bob can now pass it on himself.
    assert club.get(club.bob)["can_hand_over"] is True

    passed = club.hand_over(club.bob, club.cleo)
    assert passed.json()["holder"]["id"] == club.cleo.id
    assert passed.json()["queue"] == []

    back = club.hand_over(club.cleo, None)
    assert back.json()["holder"] is None
    assert back.json()["held_since"] is None
    assert club.hand_over(club.ana, None).status_code == 200  # already back: nothing logged

    logged = _logged(db_session, club.group_id)
    assert [action for action, _ in logged] == [
        "book.added",
        "book.queue_joined",
        "book.queue_joined",
        "book.lent",
        "book.lent",
        "book.returned",
    ]
    assert logged[4][1] == {
        "title": "Dune",
        "to": club.cleo.id,
        "to_name": club.cleo.body["user"]["display_name"],
    }


def test_handing_to_the_owner_means_returned(client: TestClient) -> None:
    club = Club(client)
    club.hand_over(club.ana, club.bob)

    response = club.hand_over(club.bob, club.ana)

    assert response.json()["holder"] is None


def test_only_the_owner_holder_or_an_admin_hands_over(client: TestClient) -> None:
    club = Club(client)
    club.hand_over(club.ana, club.bob)

    assert club.hand_over(club.cleo, club.cleo).status_code == 403
    assert club.hand_over(club.owner, club.cleo).status_code == 200  # admin+


def test_the_recipient_must_be_a_member(client: TestClient) -> None:
    club = Club(client)
    outsider = register(client)

    for to in (outsider.id, str(uuid.uuid4())):
        response = club.hand_over(club.ana, to)
        assert response.status_code == 422
        assert response.json()["code"] == "invalid_reference"
        assert response.json()["errors"][0]["field"] == "to_user_id"


# --- leaving ------------------------------------------------------------------------------


def test_a_leaver_takes_their_books_returns_the_rest_and_leaves_queues(
    client: TestClient,
) -> None:
    club = Club(client)
    bobs = create_book(client, club.bob, club.group_id, title="Bob's own")
    club.hand_over(club.ana, club.bob)  # Bob has Ana's Dune
    other = create_book(client, club.cleo, club.group_id, title="Cleo's")
    client.put(f"/api/v1/books/{other['id']}/queue", headers=club.bob.headers)

    left = client.delete(
        f"/api/v1/groups/{club.group_id}/members/{club.bob.id}", headers=club.bob.headers
    )
    assert left.status_code == 204

    titles = [
        b["title"]
        for b in client.get(
            f"/api/v1/groups/{club.group_id}/books", headers=club.ana.headers
        ).json()
    ]
    assert titles == ["Cleo's", "Dune"]
    assert bobs["title"] not in titles
    assert club.get(club.ana)["holder"] is None
    cleos = client.get(f"/api/v1/books/{other['id']}", headers=club.cleo.headers).json()
    assert cleos["queue"] == []


# --- the feed -----------------------------------------------------------------------------


def test_the_feed_tells_who_lent_what_to_whom(client: TestClient) -> None:
    club = Club(client)
    club.hand_over(club.ana, club.bob)
    club.hand_over(club.bob, None)

    feed = client.get(f"/api/v1/groups/{club.group_id}/feed", headers=club.cleo.headers).json()
    books = [item for item in feed["items"] if item["subject_type"] == "book"]

    assert [item["action"] for item in books] == ["book.returned", "book.lent", "book.added"]
    assert books[1]["data"] == {"to_name": club.bob.body["user"]["display_name"]}
    assert {item["subject_title"] for item in books} == {"Dune"}
    assert all(item["subject_exists"] for item in books)
