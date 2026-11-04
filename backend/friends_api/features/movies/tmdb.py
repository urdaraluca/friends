"""Movie auto-fill from TMDB (contract section 19).

The key stays on the server; only api.themoviedb.org is ever fetched. TMDB has no IMDb rating:
its own score (``vote_average``, 0-10) is what the app puts in the Movie night ``imdb_rating``
field. The IMDb link comes from TMDB's external IDs.
"""

import logging
from dataclasses import dataclass
from typing import Any

import httpx2

from friends_api.features.books.isbn import LookupUnavailable

logger = logging.getLogger(__name__)

TMDB_API = "https://api.themoviedb.org/3"
POSTER_BASE = "https://image.tmdb.org/t/p/w185"
TIMEOUT_SECONDS = 5.0
MAX_RESULTS = 10

GENRES = {
    "Action": "Action",
    "Adventure": "Action",
    "Comedy": "Comedy",
    "Drama": "Drama",
    "Horror": "Horror",
    "Science Fiction": "Sci-fi",
    "Animation": "Animation",
    "Documentary": "Documentary",
    "Thriller": "Thriller",
    "Crime": "Thriller",
    "Mystery": "Thriller",
    "Romance": "Romance",
}
"""TMDB genre names (asked for in English) to the Movie night ``genre`` options (section 6.5)."""


@dataclass(frozen=True, slots=True)
class MovieHit:
    tmdb_id: int
    title: str
    original_title: str | None
    year: int | None
    overview: str | None
    poster_url: str | None


@dataclass(frozen=True, slots=True)
class MovieDetails(MovieHit):
    runtime_min: int | None
    rating: float | None
    genres: list[str]
    genre: str | None
    imdb_url: str | None


def _year(date: Any) -> int | None:
    if isinstance(date, str) and len(date) >= 4 and date[:4].isdigit():
        return int(date[:4])
    return None


def _text(value: Any) -> str | None:
    return value.strip() if isinstance(value, str) and value.strip() else None


def _poster(path: Any) -> str | None:
    return f"{POSTER_BASE}{path}" if isinstance(path, str) and path.startswith("/") else None


def _hit(raw: dict[str, Any]) -> MovieHit | None:
    title = _text(raw.get("title"))
    if not isinstance(raw.get("id"), int) or title is None:
        return None
    original = _text(raw.get("original_title"))
    return MovieHit(
        tmdb_id=raw["id"],
        title=title,
        original_title=original if original != title else None,
        year=_year(raw.get("release_date")),
        overview=_text(raw.get("overview")),
        poster_url=_poster(raw.get("poster_path")),
    )


def _language(locale: str | None) -> str:
    """TMDB's ``language``: titles and overviews in the user's language when TMDB has them."""
    return "ro-RO" if (locale or "").lower().startswith("ro") else "en-US"


class MovieLookup:
    """Tests give it an ``httpx2.Client`` with a mock transport."""

    def __init__(self, client: httpx2.Client, api_key: str | None) -> None:
        self._client = client
        self._api_key = api_key

    @classmethod
    def create(cls, api_key: str | None) -> MovieLookup:
        client = httpx2.Client(
            timeout=TIMEOUT_SECONDS, headers={"User-Agent": "FriendsApp/1 (movie lookup)"}
        )
        return cls(client, api_key)

    @property
    def available(self) -> bool:
        return bool(self._api_key)

    def close(self) -> None:
        self._client.close()

    def _get(self, path: str, params: dict[str, Any]) -> dict[str, Any] | None:
        """TMDB's JSON for ``path``; None for a 404. Raises LookupUnavailable otherwise."""
        if not self._api_key:
            raise LookupUnavailable("Movie search isn't set up on this server.")
        try:
            response = self._client.get(
                f"{TMDB_API}{path}", params={**params, "api_key": self._api_key}
            )
        except httpx2.HTTPError as exc:
            logger.warning("TMDB request failed: %s", type(exc).__name__)
            raise LookupUnavailable("Couldn't reach TMDB, try again later.") from exc
        if response.status_code == 404:
            return None
        if response.status_code != 200:
            logger.warning("TMDB answered %s for %s", response.status_code, path)
            raise LookupUnavailable("Couldn't reach TMDB, try again later.")
        body = response.json()
        return body if isinstance(body, dict) else None

    def search(self, query: str, *, year: int | None, locale: str | None) -> list[MovieHit]:
        params: dict[str, Any] = {
            "query": query,
            "include_adult": "false",
            "language": _language(locale),
        }
        if year is not None:
            params["year"] = year
        body = self._get("/search/movie", params) or {}
        results = body.get("results")
        hits = (
            [_hit(raw) for raw in results if isinstance(raw, dict)]
            if isinstance(results, list)
            else []
        )
        return [hit for hit in hits if hit is not None][:MAX_RESULTS]

    def details(self, tmdb_id: int, *, locale: str | None) -> MovieDetails | None:
        raw = self._get(
            f"/movie/{tmdb_id}",
            {"language": _language(locale), "append_to_response": "external_ids"},
        )
        if raw is None:
            return None
        hit = _hit(raw)
        if hit is None:
            return None
        english = self._genre_names(tmdb_id, raw, locale)
        genre = next(
            (GENRES[name] for name in english if name in GENRES), "Other" if english else None
        )
        names = [
            g["name"]
            for g in raw.get("genres") or []
            if isinstance(g, dict) and isinstance(g.get("name"), str)
        ]
        runtime = raw.get("runtime")
        votes, average = raw.get("vote_count"), raw.get("vote_average")
        rating = (
            round(float(average), 1)
            if isinstance(average, int | float) and isinstance(votes, int) and votes > 0
            else None
        )
        imdb_id = (raw.get("external_ids") or {}).get("imdb_id") or raw.get("imdb_id")
        return MovieDetails(
            tmdb_id=hit.tmdb_id,
            title=hit.title,
            original_title=hit.original_title,
            year=hit.year,
            overview=hit.overview,
            poster_url=hit.poster_url,
            runtime_min=runtime if isinstance(runtime, int) and 1 <= runtime <= 600 else None,
            rating=rating,
            genres=names,
            genre=genre,
            imdb_url=f"https://www.imdb.com/title/{imdb_id}/"
            if isinstance(imdb_id, str) and imdb_id.startswith("tt")
            else None,
        )

    def _genre_names(self, tmdb_id: int, raw: dict[str, Any], locale: str | None) -> list[str]:
        """The English genre names, which the ``genre`` options are matched against: TMDB
        translates them with ``language``."""
        if _language(locale) == "en-US":
            source: dict[str, Any] | None = raw
        else:
            source = self._get(f"/movie/{tmdb_id}", {"language": "en-US"})
        genres = (source or {}).get("genres") or []
        return [g["name"] for g in genres if isinstance(g, dict) and isinstance(g.get("name"), str)]
