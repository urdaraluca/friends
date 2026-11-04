from typing import Annotated

from fastapi import APIRouter, Depends, Query, Request
from pydantic import BaseModel

from friends_api.core.errors import NotFound
from friends_api.core.ratelimit import limit_by_ip
from friends_api.deps import CurrentUser
from friends_api.features.movies.tmdb import MovieLookup

router = APIRouter(tags=["movies"])


class MovieSearchResult(BaseModel):
    tmdb_id: int
    title: str
    original_title: str | None
    """Set only when it differs from ``title``."""
    year: int | None
    overview: str | None
    poster_url: str | None
    """An https image on image.tmdb.org, to preview."""


class Movie(MovieSearchResult):
    """What the activity form fills in (contract section 19)."""

    runtime_min: int | None
    rating: float | None
    """TMDB's score, 0-10 with one decimal; null without votes. The app puts it in the
    ``imdb_rating`` field (TMDB has no IMDb rating)."""
    genres: list[str]
    """TMDB's genre names, in the user's language."""
    genre: str | None
    """The matching Movie night ``genre`` option (section 6.5), ``Other``, or null."""
    imdb_url: str | None


def get_movie_lookup(request: Request) -> MovieLookup:
    lookup: MovieLookup = request.app.state.movie_lookup
    return lookup


Lookup = Annotated[MovieLookup, Depends(get_movie_lookup)]


@router.get("/movies/search", dependencies=[Depends(limit_by_ip("movie_lookup"))])
def search_movies(
    user: CurrentUser,
    lookup: Lookup,
    query: Annotated[str, Query(min_length=1, max_length=200)],
    year: Annotated[int | None, Query(ge=1870, le=2100)] = None,
) -> list[MovieSearchResult]:
    """Up to 10 TMDB matches, in my language when TMDB has it. 503 ``lookup_unavailable``
    when the server has no TMDB key or TMDB can't be reached."""
    hits = lookup.search(query.strip(), year=year, locale=user.locale)
    return [MovieSearchResult.model_validate(hit, from_attributes=True) for hit in hits]


@router.get("/movies/{tmdb_id}", dependencies=[Depends(limit_by_ip("movie_lookup"))])
def get_movie(tmdb_id: int, user: CurrentUser, lookup: Lookup) -> Movie:
    """One movie's details for the activity form."""
    details = lookup.details(tmdb_id, locale=user.locale)
    if details is None:
        raise NotFound("TMDB doesn't know this movie.")
    return Movie.model_validate(details, from_attributes=True)
