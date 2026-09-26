"""Filtering the backlog and the wheel by custom attributes (issue #18)."""

import uuid
from typing import Any

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import update
from sqlalchemy.orm import Session

from friends_api.features.activities.models import Activity
from tests.factories import Account, create_activity, create_group, list_categories, register


class Movies:
    """Movies in the default Movie night category (genre select, imdb_rating 0-10, year)."""

    def __init__(self, client: TestClient) -> None:
        self.client = client
        self.owner = register(client)
        self.group = create_group(client, self.owner)
        self.gid = self.group["id"]
        movie_night = next(
            c for c in list_categories(client, self.owner, self.gid) if c["name"] == "Movie night"
        )
        self.titles: dict[str, str] = {}
        for title, attributes in [
            ("Alien", {"genre": "Sci-fi", "imdb_rating": 8.5, "year": 1979}),
            ("Airplane!", {"genre": "Comedy", "imdb_rating": 7.7, "year": 1980}),
            ("Cats", {"genre": "Comedy", "imdb_rating": 2.8, "year": 2019}),
            ("Untitled", {}),
        ]:
            activity = create_activity(
                client,
                self.owner,
                self.gid,
                title=title,
                category_id=movie_night["id"],
                attributes=attributes,
            )
            self.titles[activity["id"]] = title

    def titles_for(self, *attr: str, owner: Account | None = None) -> list[str]:
        params: list[tuple[str, str | int | float | bool | None]] = [("attr", a) for a in attr]
        params += [("sort", "title"), ("order", "asc")]
        response = self.client.get(
            f"/api/v1/groups/{self.gid}/activities",
            headers=(owner or self.owner).headers,
            params=params,
        )
        assert response.status_code == 200, response.text
        return [item["title"] for item in response.json()["items"]]


@pytest.fixture
def movies(client: TestClient) -> Movies:
    return Movies(client)


@pytest.mark.parametrize(
    ("attr", "titles"),
    [
        (["imdb_rating:gte:7.5"], ["Airplane!", "Alien"]),
        (["imdb_rating:lte:7.7"], ["Airplane!", "Cats"]),
        (["genre:eq:comedy"], ["Airplane!", "Cats"]),  # ASCII case-insensitive
        (["genre:eq:Comedy", "imdb_rating:gte:5"], ["Airplane!"]),  # all must match
        (["genre:contains:fi"], ["Alien"]),
        (["year:eq:1980"], ["Airplane!"]),
        (["year:gte:1980", "year:lte:2000"], ["Airplane!"]),
        (["genre:eq:Horror"], []),
        (["unknown_key:eq:x"], []),
    ],
)
def test_attribute_filters(movies: Movies, attr: list[str], titles: list[str]) -> None:
    assert movies.titles_for(*attr) == titles


def test_a_value_of_another_type_never_matches(movies: Movies, db_session: Session) -> None:
    # Text left in a field that is now a number: not "greater" than any number.
    alien = next(k for k, v in movies.titles.items() if v == "Alien")
    db_session.execute(
        update(Activity)
        .where(Activity.id == uuid.UUID(alien))
        .values(attributes={"genre": "Sci-fi", "imdb_rating": "very good"})
    )
    db_session.commit()

    assert movies.titles_for("imdb_rating:gte:0") == ["Airplane!", "Cats"]
    assert movies.titles_for("imdb_rating:eq:very good") == ["Alien"]


def test_a_value_with_colons_is_kept_whole(movies: Movies) -> None:
    assert movies.titles_for("genre:eq:Sci:fi") == []


@pytest.mark.parametrize(
    ("attr", "message"),
    [
        ("imdb_rating", "Use key:op:value, e.g. imdb_rating:gte:7.5."),
        ("imdb_rating:gte:high", "gte and lte need a number."),
        ("imdb_rating:lte:nan", "gte and lte need a number."),
        ("imdb_rating:like:7", None),
        ("Bad-Key:eq:x", None),
        ("genre:eq:", None),
    ],
)
def test_malformed_filters_are_a_422(movies: Movies, attr: str, message: str | None) -> None:
    response = movies.client.get(
        f"/api/v1/groups/{movies.gid}/activities",
        headers=movies.owner.headers,
        params=[("attr", "genre:eq:Comedy"), ("attr", attr)],
    )

    assert response.status_code == 422
    error = response.json()["errors"][0]
    assert error["field"] == "query.attr.1"
    if message is not None:
        assert error["message"] == message


def test_at_most_five_filters(movies: Movies) -> None:
    response = movies.client.get(
        f"/api/v1/groups/{movies.gid}/activities",
        headers=movies.owner.headers,
        params=[("attr", "year:gte:1900")] * 6,
    )

    assert response.status_code == 422


def test_the_wheel_filters_by_attributes_too(movies: Movies) -> None:
    client, gid = movies.client, movies.gid
    candidates = client.get(
        f"/api/v1/groups/{gid}/wheel/candidates",
        headers=movies.owner.headers,
        params=[("attr", "genre:eq:Comedy"), ("attr", "imdb_rating:gte:5")],
    )
    assert candidates.status_code == 200, candidates.text
    assert [a["title"] for a in candidates.json()["items"]] == ["Airplane!"]

    spin_filters: dict[str, Any] = {
        "attributes": [{"key": "imdb_rating", "op": "gte", "value": "5"}],
    }
    spin = client.post(
        f"/api/v1/groups/{gid}/wheel/spins",
        headers=movies.owner.headers,
        json={"filters": spin_filters},
    )
    assert spin.status_code == 201, spin.text
    body = spin.json()
    assert sorted(c["title"] for c in body["candidates"]) == ["Airplane!", "Alien"]
    assert body["filters"]["attributes"] == [{"key": "imdb_rating", "op": "gte", "value": "5"}]

    bad = client.post(
        f"/api/v1/groups/{gid}/wheel/spins",
        headers=movies.owner.headers,
        json={"filters": {"attributes": [{"key": "imdb_rating", "op": "gte", "value": "x"}]}},
    )
    assert bad.status_code == 422
