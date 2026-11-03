"""Movie auto-fill (contract section 19): ``/movies/search`` and ``/movies/{tmdb_id}``, against a
fake TMDB."""

from typing import Any

import httpx2
from fastapi import FastAPI
from fastapi.testclient import TestClient

from friends_api.features.movies.tmdb import MovieLookup
from tests.factories import register

DUNE = {
    "id": 438631,
    "title": "Dune",
    "original_title": "Dune",
    "release_date": "2021-09-15",
    "overview": "Paul Atreides ...",
    "poster_path": "/d5NXSklXo0qyIYkgV94XAgMIckC.jpg",
}


def fake_tmdb(app: FastAPI, requests: list[httpx2.Request], *, key: str | None = "k") -> None:
    def handle(request: httpx2.Request) -> httpx2.Response:
        requests.append(request)
        path, language = request.url.path, request.url.params.get("language")
        if path == "/3/search/movie":
            return httpx2.Response(200, json={"results": [DUNE, {"id": 1}, {"title": "No id"}]})
        if path == "/3/movie/438631":
            genres = (
                [{"id": 878, "name": "SF"}, {"id": 12, "name": "Aventuri"}]
                if language == "ro-RO"
                else [{"id": 878, "name": "Science Fiction"}, {"id": 12, "name": "Adventure"}]
            )
            return httpx2.Response(
                200,
                json={
                    **DUNE,
                    "runtime": 155,
                    "genres": genres,
                    "vote_average": 7.788,
                    "vote_count": 12345,
                    "external_ids": {"imdb_id": "tt1160419"},
                },
            )
        if path == "/3/movie/7":
            return httpx2.Response(500)
        return httpx2.Response(404, json={})

    app.state.movie_lookup = MovieLookup(httpx2.Client(transport=httpx2.MockTransport(handle)), key)


def test_searching_and_filling_a_movie(app: FastAPI, client: TestClient) -> None:
    requests: list[httpx2.Request] = []
    fake_tmdb(app, requests)
    account = register(client)

    found = client.get(
        "/api/v1/movies/search", headers=account.headers, params={"query": " dune ", "year": 2021}
    )
    movie = client.get("/api/v1/movies/438631", headers=account.headers)

    assert found.status_code == 200
    assert found.json() == [
        {
            "tmdb_id": 438631,
            "title": "Dune",
            "original_title": None,
            "year": 2021,
            "overview": "Paul Atreides ...",
            "poster_url": "https://image.tmdb.org/t/p/w185/d5NXSklXo0qyIYkgV94XAgMIckC.jpg",
        }
    ]
    search = requests[0].url.params
    assert (search["query"], search["year"], search["language"]) == ("dune", "2021", "en-US")
    assert search["api_key"] == "k"
    body: dict[str, Any] = movie.json()
    assert body["runtime_min"] == 155
    assert body["rating"] == 7.8
    assert body["genres"] == ["Science Fiction", "Adventure"]
    assert body["genre"] == "Sci-fi"
    assert body["imdb_url"] == "https://www.imdb.com/title/tt1160419/"


def test_romanian_users_get_romanian_names_and_the_same_genre_option(
    app: FastAPI, client: TestClient
) -> None:
    requests: list[httpx2.Request] = []
    fake_tmdb(app, requests)
    account = register(client)
    me = client.get("/api/v1/me", headers=account.headers).json()
    client.put(
        "/api/v1/me",
        headers=account.headers,
        json={"display_name": me["display_name"], "timezone": me["timezone"], "locale": "ro"},
    )

    movie = client.get("/api/v1/movies/438631", headers=account.headers).json()

    assert movie["genres"] == ["SF", "Aventuri"]
    assert movie["genre"] == "Sci-fi"  # matched on TMDB's English names


def test_unknown_movies_errors_and_no_key(app: FastAPI, client: TestClient) -> None:
    requests: list[httpx2.Request] = []
    fake_tmdb(app, requests)
    account = register(client)

    assert client.get("/api/v1/movies/99", headers=account.headers).status_code == 404
    broken = client.get("/api/v1/movies/7", headers=account.headers)
    assert broken.status_code == 503
    assert broken.json()["code"] == "lookup_unavailable"

    fake_tmdb(app, requests, key=None)
    count = len(requests)
    unset = client.get("/api/v1/movies/search", headers=account.headers, params={"query": "x"})
    assert unset.status_code == 503
    assert len(requests) == count  # nothing was asked without a key


def test_signing_in_is_needed(client: TestClient) -> None:
    assert client.get("/api/v1/movies/search", params={"query": "x"}).status_code == 401
