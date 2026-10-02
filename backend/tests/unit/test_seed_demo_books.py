from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from friends_api import cli
from friends_api.core.config import Settings
from friends_api.demo.context import DEMO_EMAILS, DEMO_PASSWORD
from friends_api.features.books.models import Book
from friends_api.main import create_app


def test_seed_demo_creates_a_book_archive(settings: Settings, db_session: Session) -> None:
    assert cli.main(["seed-demo"], settings) == 0

    books = db_session.scalars(select(Book)).all()
    assert len(books) == 8
    assert len({book.owner_id for book in books}) == 3

    with TestClient(create_app(settings)) as client:
        login = client.post(
            "/api/v1/auth/login", json={"email": DEMO_EMAILS[2], "password": DEMO_PASSWORD}
        )
        headers = {"Authorization": f"Bearer {login.json()['tokens']['access_token']}"}
        listed = client.get(f"/api/v1/groups/{books[0].group_id}/books", headers=headers).json()
    by_title = {book["title"]: book for book in listed}
    dune = by_title["Dune"]
    assert (dune["owner"]["display_name"], dune["holder"]["display_name"]) == ("Ana", "Bogdan")
    assert [entry["user"]["display_name"] for entry in dune["queue"]] == ["Carla"]
    assert dune["in_my_queue"] is True  # Carla is signed in
    assert by_title["The Hobbit"]["holder"] is None
    assert by_title["The Hobbit"]["can_edit"] is True  # Carla's own
