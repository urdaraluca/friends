"""Book details, owner and holder on add, covers, ratings and the ISBN lookup (contract
sections 17.2, 17.3 and 17.5)."""

import json
from collections.abc import Callable
from typing import Any

import httpx2
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from friends_api.features.books.isbn import BookLookup
from tests.api.test_books import Club, _logged
from tests.factories import TINY_JPEG, create_book

PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 32


def _books(client: TestClient, club: Club) -> list[dict[str, Any]]:
    response = client.get(f"/api/v1/groups/{club.group_id}/books", headers=club.ana.headers)
    assert response.status_code == 200, response.text
    books: list[dict[str, Any]] = response.json()
    return books


def _put(client: TestClient, club: Club, account: Any, **fields: Any) -> Any:
    body = {"title": "Dune", "author": "Someone", "description": "Spice.", **fields}
    return client.put(f"/api/v1/books/{club.book_id}", headers=account.headers, json=body)


# --- details ------------------------------------------------------------------------------


def test_details_round_trip_and_isbn_10_becomes_13(client: TestClient) -> None:
    club = Club(client)

    book = create_book(
        client,
        club.bob,
        club.group_id,
        title="Dune",
        isbn="0-441-17271-7",
        genre="sci_fi",
        language="EN",
    )

    assert (book["isbn"], book["genre"], book["language"]) == ("9780441172719", "sci_fi", "en")
    assert book["cover_updated_at"] is None
    assert (book["rating_average"], book["rating_count"], book["my_rating"]) == (None, 0, None)


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("isbn", "9780441172718"),  # wrong check digit
        ("isbn", "12345"),
        ("genre", "cookbooks"),
        ("language", "eng"),
        ("language", "e1"),
    ],
)
def test_bad_details_are_rejected(client: TestClient, field: str, value: str) -> None:
    club = Club(client)

    response = client.post(
        f"/api/v1/groups/{club.group_id}/books",
        headers=club.ana.headers,
        json={"title": "X", field: value},
    )

    assert response.status_code == 422, response.text
    assert response.json()["errors"][0]["field"] == field


def test_blank_details_mean_none(client: TestClient) -> None:
    club = Club(client)

    book = create_book(client, club.ana, club.group_id, isbn=" ", genre="", language="")

    assert (book["isbn"], book["genre"], book["language"]) == (None, None, None)


def test_editing_details_logs_the_fields(client: TestClient, db_session: Session) -> None:
    club = Club(client)

    response = _put(client, club, club.ana, genre="sci_fi", language="ro")

    assert response.status_code == 200, response.text
    assert (response.json()["genre"], response.json()["language"]) == ("sci_fi", "ro")
    assert _logged(db_session, club.group_id)[-1] == (
        "book.updated",
        {"title": "Dune", "fields": ["genre", "language"]},
    )


# --- owner and holder ---------------------------------------------------------------------


def test_adding_a_book_for_someone_else_who_lent_it_on(
    client: TestClient, db_session: Session
) -> None:
    club = Club(client)

    book = create_book(
        client,
        club.ana,
        club.group_id,
        title="Emma",
        owner_id=club.bob.id,
        holder_id=club.cleo.id,
    )

    assert book["owner"]["id"] == club.bob.id
    assert book["holder"]["id"] == club.cleo.id
    assert book["held_since"] is not None
    assert book["can_edit"] is True  # Bob's book, but Ana added it: she may fix it
    assert (
        client.get(f"/api/v1/books/{book['id']}", headers=club.cleo.headers).json()["can_edit"]
        is False
    )
    actions = [action for action, _ in _logged(db_session, club.group_id)]
    assert actions[-2:] == ["book.added", "book.lent"]


def test_a_holder_who_is_the_owner_means_with_the_owner(client: TestClient) -> None:
    club = Club(client)

    book = create_book(client, club.ana, club.group_id, owner_id=club.bob.id, holder_id=club.bob.id)

    assert book["holder"] is None


@pytest.mark.parametrize("field", ["owner_id", "holder_id"])
def test_owner_and_holder_must_be_members(client: TestClient, field: str) -> None:
    club = Club(client)
    outsider = Club(client).ana

    response = client.post(
        f"/api/v1/groups/{club.group_id}/books",
        headers=club.ana.headers,
        json={"title": "X", field: outsider.id},
    )

    assert response.status_code == 422
    assert response.json()["code"] == "invalid_reference"
    assert response.json()["errors"][0]["field"] == field


def test_changing_the_owner(client: TestClient, db_session: Session) -> None:
    club = Club(client)
    club.hand_over(club.ana, club.bob)
    club.queue(club.cleo)

    to_bob = _put(client, club, club.ana, owner_id=club.bob.id)

    assert to_bob.status_code == 200, to_bob.text
    book = to_bob.json()
    # Bob had it, so it is with its (new) owner now.
    assert (book["owner"]["id"], book["holder"]) == (club.bob.id, None)
    assert _logged(db_session, club.group_id)[-1][1]["fields"] == ["owner"]

    to_cleo = _put(client, club, club.bob, owner_id=club.cleo.id)
    assert to_cleo.json()["queue"] == []  # Cleo no longer waits for her own book
    # Bob isn't the owner any more (Ana still may edit it: she added it).
    assert _put(client, club, club.bob, owner_id=club.bob.id).status_code == 403
    assert _put(client, club, club.ana, owner_id=club.ana.id).status_code == 200


def test_null_owner_keeps_the_owner(client: TestClient) -> None:
    club = Club(client)

    response = _put(client, club, club.owner, owner_id=None)

    assert response.json()["owner"]["id"] == club.ana.id


# --- covers -------------------------------------------------------------------------------


def _upload(client: TestClient, club: Club, account: Any, data: bytes, name: str = "c.jpg") -> Any:
    return client.put(
        f"/api/v1/books/{club.book_id}/cover",
        headers=account.headers,
        files={"file": (name, data, "application/octet-stream")},
    )


def test_uploading_and_reading_a_cover(client: TestClient) -> None:
    club = Club(client)

    uploaded = _upload(client, club, club.ana, TINY_JPEG)

    assert uploaded.status_code == 200, uploaded.text
    assert uploaded.json()["cover_updated_at"] is not None
    cover = client.get(f"/api/v1/books/{club.book_id}/cover", headers=club.bob.headers)
    assert cover.status_code == 200
    assert cover.content == TINY_JPEG
    assert cover.headers["content-type"] == "image/jpeg"
    etag = cover.headers["etag"]
    again = client.get(
        f"/api/v1/books/{club.book_id}/cover",
        headers={**club.bob.headers, "If-None-Match": etag},
    )
    assert again.status_code == 304

    replaced = _upload(client, club, club.ana, PNG, "c.png")
    assert replaced.json()["cover_updated_at"] >= uploaded.json()["cover_updated_at"]
    assert (
        client.get(f"/api/v1/books/{club.book_id}/cover", headers=club.bob.headers).headers[
            "content-type"
        ]
        == "image/png"
    )


def test_a_cover_must_be_a_small_image(client: TestClient) -> None:
    club = Club(client)

    not_image = _upload(client, club, club.ana, b"GIF89a not allowed")
    too_big = _upload(client, club, club.ana, TINY_JPEG + b"\x00" * (2 * 1024 * 1024))

    for response in (not_image, too_big):
        assert response.status_code == 422
        assert response.json()["code"] == "invalid_image"


def test_only_the_owner_the_adder_or_an_admin_changes_the_cover(client: TestClient) -> None:
    club = Club(client)
    # Bob adds Cleo's book, and photographs it.
    cleos = create_book(client, club.bob, club.group_id, owner_id=club.cleo.id)

    assert _upload(client, club, club.bob, TINY_JPEG).status_code == 403
    assert _upload(client, club, club.owner, TINY_JPEG).status_code == 200
    bobs_upload = client.put(
        f"/api/v1/books/{cleos['id']}/cover",
        headers=club.bob.headers,
        files={"file": ("c.jpg", TINY_JPEG, "image/jpeg")},
    )
    assert bobs_upload.status_code == 200


def test_removing_a_cover(client: TestClient) -> None:
    club = Club(client)
    _upload(client, club, club.ana, TINY_JPEG)

    removed = client.delete(f"/api/v1/books/{club.book_id}/cover", headers=club.ana.headers)

    assert removed.status_code == 200
    assert removed.json()["cover_updated_at"] is None
    missing = client.get(f"/api/v1/books/{club.book_id}/cover", headers=club.ana.headers)
    assert missing.status_code == 404
    again = client.delete(f"/api/v1/books/{club.book_id}/cover", headers=club.ana.headers)
    assert again.status_code == 200  # idempotent


# --- ratings ------------------------------------------------------------------------------


def _rate(client: TestClient, club: Club, account: Any, stars: int | None) -> Any:
    url = f"/api/v1/books/{club.book_id}/rating"
    if stars is None:
        return client.delete(url, headers=account.headers)
    return client.put(url, headers=account.headers, json={"stars": stars})


def test_rating_a_book(client: TestClient) -> None:
    club = Club(client)

    assert _rate(client, club, club.ana, 5).status_code == 200  # the owner may rate too
    _rate(client, club, club.bob, 4)
    _rate(client, club, club.cleo, 4)
    rerated = _rate(client, club, club.cleo, 3)

    book = rerated.json()
    assert (book["rating_average"], book["rating_count"], book["my_rating"]) == (4.0, 3, 3)
    assert club.get(club.owner)["my_rating"] is None
    assert club.get(club.bob)["my_rating"] == 4
    listed = _books(client, club)[0]
    assert (listed["rating_average"], listed["my_rating"]) == (4.0, 5)

    unrated = _rate(client, club, club.cleo, None)
    assert (unrated.json()["rating_average"], unrated.json()["rating_count"]) == (4.5, 2)
    assert _rate(client, club, club.cleo, None).status_code == 200  # idempotent


def test_the_average_has_one_decimal(client: TestClient) -> None:
    club = Club(client)
    for account, stars in ((club.ana, 5), (club.bob, 4), (club.cleo, 4)):
        _rate(client, club, account, stars)

    assert club.get(club.ana)["rating_average"] == 4.3


@pytest.mark.parametrize("stars", [0, 6])
def test_stars_go_from_one_to_five(client: TestClient, stars: int) -> None:
    club = Club(client)

    assert _rate(client, club, club.bob, stars).status_code == 422


def test_a_leaver_takes_their_ratings(client: TestClient) -> None:
    club = Club(client)
    _rate(client, club, club.bob, 1)
    _rate(client, club, club.cleo, 5)

    client.delete(f"/api/v1/groups/{club.group_id}/members/{club.bob.id}", headers=club.bob.headers)

    assert (club.get(club.ana)["rating_average"], club.get(club.ana)["rating_count"]) == (5.0, 1)


# --- ISBN lookup ----------------------------------------------------------------------------

Handler = Callable[[httpx2.Request], httpx2.Response]

GOOGLE_DUNE = {
    "items": [
        {
            "volumeInfo": {
                "title": "Dune",
                "authors": ["Frank Herbert"],
                "description": "<p>Set on the desert planet Arrakis.</p>",
                "categories": ["Fiction / Science Fiction / General"],
                "language": "en",
                "imageLinks": {
                    "thumbnail": "http://books.google.com/books/content?id=x&zoom=1&edge=curl"
                },
            }
        }
    ]
}

OPEN_LIBRARY_DUNE = {
    "ISBN:9780441172719": {
        "title": "Dune",
        "authors": [{"url": "https://openlibrary.org/authors/OL1A", "name": "Frank Herbert"}],
        "subjects": [{"name": "Science fiction"}, {"name": "Fiction, science fiction, general"}],
        "cover": {"large": "https://covers.openlibrary.org/b/id/12345-L.jpg"},
    }
}
OPEN_LIBRARY_EDITION = {"languages": [{"key": "/languages/eng"}], "works": [{"key": "/works/OL1W"}]}
OPEN_LIBRARY_WORK = {
    "description": {"type": "/type/text", "value": "A desert planet."},
    "subjects": ["Comic books, strips"],  # noise: outvoted
}


def _open_library(request: httpx2.Request) -> httpx2.Response:
    """Open Library's three answers: the book, its edition and its work."""
    path = request.url.path
    if path == "/api/books":
        return _json(OPEN_LIBRARY_DUNE)
    if path == "/isbn/9780441172719.json":
        return _json(OPEN_LIBRARY_EDITION)
    if path == "/works/OL1W.json":
        return _json(OPEN_LIBRARY_WORK)
    return httpx2.Response(404)


def _use_catalogues(app: FastAPI, handler: Handler) -> list[str]:
    """Answers the lookup's requests with ``handler``; returns the URLs it asked for."""
    asked: list[str] = []

    def recording(request: httpx2.Request) -> httpx2.Response:
        asked.append(str(request.url))
        return handler(request)

    app.state.book_lookup = BookLookup(httpx2.Client(transport=httpx2.MockTransport(recording)))
    return asked


def _json(body: object, status: int = 200) -> httpx2.Response:
    return httpx2.Response(
        status, content=json.dumps(body).encode(), headers={"content-type": "application/json"}
    )


def _look_up(client: TestClient, club: Club, isbn: str) -> Any:
    return client.get(f"/api/v1/books/isbn/{isbn}", headers=club.ana.headers)


def test_google_books_answers(app: FastAPI, client: TestClient) -> None:
    club = Club(client)
    asked = _use_catalogues(app, lambda request: _json(GOOGLE_DUNE))

    response = _look_up(client, club, "0441172717")

    assert response.status_code == 200, response.text
    assert response.json() == {
        "isbn": "9780441172719",
        "title": "Dune",
        "author": "Frank Herbert",
        "description": "Set on the desert planet Arrakis.",
        "genre": "sci_fi",
        "language": "en",
        "cover_url": "https://books.google.com/books/content?id=x&zoom=1",
    }
    assert len(asked) == 1
    assert "isbn%3A9780441172719" in asked[0]


def test_open_library_fills_what_google_lacks(app: FastAPI, client: TestClient) -> None:
    club = Club(client)
    sparse = {"items": [{"volumeInfo": {"title": "Dune", "authors": ["F. Herbert"]}}]}

    def handler(request: httpx2.Request) -> httpx2.Response:
        if request.url.host == "www.googleapis.com":
            return _json(sparse)
        return _open_library(request)

    _use_catalogues(app, handler)

    found = _look_up(client, club, "9780441172719").json()

    assert found["author"] == "F. Herbert"  # Google's answer wins
    assert found["description"] == "A desert planet."
    assert found["genre"] == "sci_fi"
    assert found["language"] == "en"
    assert found["cover_url"] == "https://covers.openlibrary.org/b/id/12345-L.jpg"


def test_open_library_answers_when_google_is_down(app: FastAPI, client: TestClient) -> None:
    club = Club(client)

    def handler(request: httpx2.Request) -> httpx2.Response:
        if request.url.host == "www.googleapis.com":
            raise httpx2.ConnectError("down")
        return _open_library(request)

    _use_catalogues(app, handler)

    assert _look_up(client, club, "9780441172719").json()["title"] == "Dune"


def test_an_unknown_isbn_is_a_404(app: FastAPI, client: TestClient) -> None:
    club = Club(client)
    _use_catalogues(
        app, lambda request: _json({"totalItems": 0} if "google" in str(request.url) else {})
    )

    response = _look_up(client, club, "9780441172719")

    assert response.status_code == 404
    assert response.json()["code"] == "not_found"


def test_both_catalogues_down_is_a_503(app: FastAPI, client: TestClient) -> None:
    club = Club(client)
    _use_catalogues(app, lambda request: httpx2.Response(500))

    response = _look_up(client, club, "9780441172719")

    assert response.status_code == 503
    assert response.json()["code"] == "lookup_unavailable"


def test_an_invalid_isbn_is_a_422(app: FastAPI, client: TestClient) -> None:
    club = Club(client)
    asked = _use_catalogues(app, lambda request: _json(GOOGLE_DUNE))

    response = _look_up(client, club, "9780441172718")

    assert response.status_code == 422
    assert response.json()["code"] == "invalid_isbn"
    assert asked == []


def test_the_lookup_needs_a_signed_in_user(client: TestClient) -> None:
    assert client.get("/api/v1/books/isbn/9780441172719").status_code == 401


# --- the ISBN's cover ---------------------------------------------------------------------


def test_using_the_isbn_cover(app: FastAPI, client: TestClient) -> None:
    club = Club(client)
    book = create_book(client, club.ana, club.group_id, title="Dune", isbn="9780441172719")

    def handler(request: httpx2.Request) -> httpx2.Response:
        if request.url.host == "www.googleapis.com":
            return _json(GOOGLE_DUNE)
        if request.url.host == "books.google.com":
            return httpx2.Response(200, content=TINY_JPEG)
        return httpx2.Response(404)

    _use_catalogues(app, handler)

    response = client.post(f"/api/v1/books/{book['id']}/cover/isbn", headers=club.ana.headers)

    assert response.status_code == 200, response.text
    assert response.json()["cover_updated_at"] is not None
    cover = client.get(f"/api/v1/books/{book['id']}/cover", headers=club.ana.headers)
    assert cover.content == TINY_JPEG


def test_falls_back_to_the_open_library_cover(app: FastAPI, client: TestClient) -> None:
    club = Club(client)
    book = create_book(client, club.ana, club.group_id, title="Dune", isbn="9780441172719")

    def handler(request: httpx2.Request) -> httpx2.Response:
        if request.url.host == "covers.openlibrary.org":
            assert request.url.params["default"] == "false"
            return httpx2.Response(200, content=PNG)
        return _json({})

    _use_catalogues(app, handler)

    response = client.post(f"/api/v1/books/{book['id']}/cover/isbn", headers=club.ana.headers)

    assert response.status_code == 200, response.text


def test_no_isbn_cover(app: FastAPI, client: TestClient) -> None:
    club = Club(client)
    with_isbn = create_book(client, club.ana, club.group_id, isbn="9780441172719")
    _use_catalogues(app, lambda request: httpx2.Response(404))

    without = client.post(f"/api/v1/books/{club.book_id}/cover/isbn", headers=club.ana.headers)
    not_found = client.post(f"/api/v1/books/{with_isbn['id']}/cover/isbn", headers=club.ana.headers)

    assert (without.status_code, without.json()["code"]) == (409, "no_isbn")
    assert (not_found.status_code, not_found.json()["code"]) == (404, "not_found")
