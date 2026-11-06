"""ISBNs, looking books up by one, and searching by title or author (contract section 17.5).

Google Books answers first (it has descriptions, categories and languages); Open Library fills
what it leaves out, or answers alone when Google doesn't know the book. Only these fixed hosts
are ever fetched, covers included, so no caller-supplied URL reaches the network.
"""

import logging
import re
from collections import Counter
from collections.abc import Callable
from dataclasses import dataclass, replace
from functools import partial
from typing import Any
from urllib.parse import urlsplit

import httpx2

from friends_api.core.errors import AppError
from friends_api.features.books.models import MAX_COVER_BYTES, BookGenre

logger = logging.getLogger(__name__)

GOOGLE_BOOKS_URL = "https://www.googleapis.com/books/v1/volumes"
OPEN_LIBRARY_HOME = "https://openlibrary.org"
OPEN_LIBRARY_URL = f"{OPEN_LIBRARY_HOME}/api/books"
OPEN_LIBRARY_COVER_URL = "https://covers.openlibrary.org/b/isbn/{isbn}-L.jpg"
OPEN_LIBRARY_SEARCH_URL = f"{OPEN_LIBRARY_HOME}/search.json"
OPEN_LIBRARY_COVER_ID_URL = "https://covers.openlibrary.org/b/id/{cover_id}-M.jpg"
MAX_SEARCH_RESULTS = 10
COVER_HOSTS = frozenset(
    {"books.google.com", "books.googleusercontent.com", "covers.openlibrary.org"}
)
TIMEOUT_SECONDS = 5.0

_SEPARATORS = re.compile(r"[\s-]")


class LookupUnavailable(AppError):
    status_code = 503
    code = "lookup_unavailable"


# --- ISBNs --------------------------------------------------------------------------------


def normalize_isbn(value: str) -> str | None:
    """The ISBN-13 for an ISBN-10 or ISBN-13 (spaces and hyphens allowed), or None when it
    isn't one (wrong length, characters or check digit)."""
    raw = _SEPARATORS.sub("", value).upper()
    if len(raw) == 10 and raw[:9].isdigit() and (raw[9].isdigit() or raw[9] == "X"):
        digits = [10 if char == "X" else int(char) for char in raw]
        if sum((10 - index) * digit for index, digit in enumerate(digits)) % 11 != 0:
            return None
        core = "978" + raw[:9]
        return core + _isbn13_check_digit(core)
    if len(raw) == 13 and raw.isdigit() and raw[:3] in ("978", "979"):
        return raw if _isbn13_check_digit(raw[:12]) == raw[12] else None
    return None


def _isbn13_check_digit(first_twelve: str) -> str:
    total = sum(int(char) * (3 if index % 2 else 1) for index, char in enumerate(first_twelve))
    return str((10 - total % 10) % 10)


# --- what a lookup finds --------------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class FoundBook:
    isbn: str
    title: str
    author: str | None = None
    description: str | None = None
    genre: BookGenre | None = None
    language: str | None = None
    cover_url: str | None = None

    def filled_from(self, other: FoundBook) -> FoundBook:
        """This, with the fields it lacks taken from ``other``."""
        return replace(
            self,
            author=self.author or other.author,
            description=self.description or other.description,
            genre=self.genre or other.genre,
            language=self.language or other.language,
            cover_url=self.cover_url or other.cover_url,
        )


@dataclass(frozen=True, slots=True)
class BookHit:
    """One search result: enough to pick the right book. With an ISBN, the app then looks it
    up for the rest (description, genre, cover)."""

    title: str
    author: str | None = None
    year: int | None = None
    isbn: str | None = None
    language: str | None = None
    cover_url: str | None = None


# Most specific first: "Juvenile Fiction" is for children, "Science Fiction" isn't just fiction.
_GENRE_KEYWORDS: tuple[tuple[BookGenre, tuple[str, ...]], ...] = (
    (BookGenre.COMICS, ("comic", "graphic novel", "manga")),
    (BookGenre.YOUNG_ADULT, ("young adult",)),
    (BookGenre.CHILDREN, ("juvenile", "children", "picture book")),
    (BookGenre.POETRY, ("poetry", "poems")),
    (BookGenre.SELF_HELP, ("self-help", "self help", "personal development")),
    (BookGenre.BIOGRAPHY, ("biography", "autobiography", "memoir")),
    (BookGenre.SCI_FI, ("science fiction", "sci-fi", "dystopia")),
    (BookGenre.FANTASY, ("fantasy",)),
    (BookGenre.MYSTERY_THRILLER, ("mystery", "thriller", "detective", "crime", "suspense")),
    (BookGenre.HORROR, ("horror",)),
    (BookGenre.ROMANCE, ("romance", "love stories")),
    (BookGenre.CLASSICS, ("classics", "classic literature")),
    (BookGenre.HISTORY, ("history",)),
    (BookGenre.FICTION, ("fiction", "novel")),
)


def guess_genre(subjects: list[str]) -> BookGenre | None:
    """The genre most of ``subjects`` name (each counts for its most specific genre), or None.
    Catalogue subjects are noisy ("Comic books, strips" on The Hobbit), so one stray subject
    doesn't decide; plain "fiction" only wins when nothing more specific is named."""
    votes: Counter[BookGenre] = Counter()
    for subject in subjects:
        text = subject.lower()
        for genre, keywords in _GENRE_KEYWORDS:
            if any(keyword in text for keyword in keywords):
                votes[genre] += 1
                break
    if not votes:
        return None
    if len(votes) > 1:
        del votes[BookGenre.FICTION]
    order = [genre for genre, _ in _GENRE_KEYWORDS]
    return max(votes, key=lambda genre: (votes[genre], -order.index(genre)))


# Open Library names languages by MARC code.
_MARC_LANGUAGES = {
    "rum": "ro",
    "ron": "ro",
    "eng": "en",
    "fre": "fr",
    "fra": "fr",
    "ger": "de",
    "deu": "de",
    "ita": "it",
    "spa": "es",
    "hun": "hu",
    "por": "pt",
    "rus": "ru",
    "dut": "nl",
    "pol": "pl",
    "gre": "el",
    "tur": "tr",
    "jpn": "ja",
    "chi": "zh",
    "swe": "sv",
    "nor": "no",
    "dan": "da",
    "fin": "fi",
    "cze": "cs",
    "ukr": "uk",
    "bul": "bg",
}


def _language(code: object) -> str | None:
    if not isinstance(code, str):
        return None
    code = code.strip().lower()
    if len(code) == 3:
        return _MARC_LANGUAGES.get(code)
    prefix = code[:2]  # "zh-CN"
    return prefix if len(prefix) == 2 and prefix.isalpha() else None


def _https(url: object) -> str | None:
    if not isinstance(url, str) or not url:
        return None
    url = url.replace("http://", "https://", 1).replace("&edge=curl", "")
    return url if urlsplit(url).hostname in COVER_HOSTS else None


def _text(value: object, limit: int) -> str | None:
    if isinstance(value, dict):  # Open Library: {"type": "/type/text", "value": "..."}
        value = value.get("value")
    if not isinstance(value, str):
        return None
    value = re.sub(r"<[^>]+>", "", value).strip()  # Google descriptions may carry HTML
    return value[:limit] or None


def parse_google(isbn: str, body: dict[str, Any]) -> FoundBook | None:
    items = body.get("items")
    if not isinstance(items, list) or not items:
        return None
    info = items[0].get("volumeInfo") or {}
    title = _text(info.get("title"), 200)
    if title is None:
        return None
    authors = [name for name in info.get("authors") or [] if isinstance(name, str)]
    categories = [name for name in info.get("categories") or [] if isinstance(name, str)]
    images = info.get("imageLinks") or {}
    return FoundBook(
        isbn=isbn,
        title=title,
        author=_text(", ".join(authors), 120),
        description=_text(info.get("description"), 5000),
        genre=guess_genre(categories),
        language=_language(info.get("language")),
        cover_url=_https(images.get("thumbnail") or images.get("smallThumbnail")),
    )


def _names(items: object) -> list[str]:
    """Open Library's ``[{"name": ...}]`` lists (authors, subjects), or plain strings."""
    if not isinstance(items, list):
        return []
    names = [item.get("name") if isinstance(item, dict) else item for item in items]
    return [name for name in names if isinstance(name, str)]


def parse_open_library(
    isbn: str,
    data: dict[str, Any],
    edition: dict[str, Any] | None = None,
    work: dict[str, Any] | None = None,
) -> FoundBook | None:
    """From Open Library's ``jscmd=data`` answer (title, authors, subjects, cover), its edition
    (language, maybe a description) and its work (description, subjects)."""
    entry = data.get(f"ISBN:{isbn}")
    if not isinstance(entry, dict):
        return None
    title = _text(entry.get("title"), 200)
    if title is None:
        return None
    edition, work = edition or {}, work or {}
    languages = [
        language["key"].rsplit("/", 1)[-1]
        for language in edition.get("languages") or []
        if isinstance(language, dict) and isinstance(language.get("key"), str)
    ]
    cover = entry.get("cover") or {}
    return FoundBook(
        isbn=isbn,
        title=title,
        author=_text(", ".join(_names(entry.get("authors"))), 120),
        description=_text(edition.get("description"), 5000) or _text(work.get("description"), 5000),
        genre=guess_genre([*_names(entry.get("subjects")), *_names(work.get("subjects"))]),
        language=_language(languages[0]) if languages else None,
        cover_url=_https(cover.get("large") or cover.get("medium")),
    )


def _year(value: object) -> int | None:
    if isinstance(value, int) and 0 < value < 10000:
        return value
    if isinstance(value, str) and len(value) >= 4 and value[:4].isdigit():
        return int(value[:4])
    return None


# ISBN-13 prefixes of the registration groups for a user's language: a work's editions come in
# no useful order (Open Library lists Circe's Swedish one first), so one from the reader's
# language area wins.
_ISBN_GROUPS = {"ro": ("978973", "978606"), "en": ("9780", "9781")}


def _isbn_groups(locale: str | None) -> tuple[str, ...]:
    return _ISBN_GROUPS["ro" if (locale or "").lower().startswith("ro") else "en"]


def _best_isbn(values: object, prefer: tuple[str, ...] = ()) -> str | None:
    """The first valid ISBN in ``values`` from one of the ``prefer`` groups, else the first
    valid one, as an ISBN-13."""
    if not isinstance(values, list):
        return None
    isbns = [
        isbn
        for value in values
        if isinstance(value, str) and (isbn := normalize_isbn(value)) is not None
    ]
    return next((isbn for isbn in isbns if isbn.startswith(prefer)), isbns[0] if isbns else None)


def parse_google_search(body: object) -> list[BookHit]:
    hits: list[BookHit] = []
    items = body.get("items") if isinstance(body, dict) else None
    for item in items if isinstance(items, list) else []:
        info = item.get("volumeInfo") if isinstance(item, dict) else None
        if not isinstance(info, dict):
            continue
        title = _text(info.get("title"), 200)
        if title is None:
            continue
        identifiers = info.get("industryIdentifiers") or []
        isbns = [
            entry.get("identifier")
            for entry in sorted(
                (e for e in identifiers if isinstance(e, dict)),
                key=lambda e: e.get("type") != "ISBN_13",  # ISBN-13 first
            )
            if entry.get("type") in ("ISBN_13", "ISBN_10")
        ]
        authors = [name for name in info.get("authors") or [] if isinstance(name, str)]
        images = info.get("imageLinks") or {}
        hits.append(
            BookHit(
                title=title,
                author=_text(", ".join(authors), 120),
                year=_year(info.get("publishedDate")),
                isbn=_best_isbn(isbns),
                language=_language(info.get("language")),
                cover_url=_https(images.get("thumbnail") or images.get("smallThumbnail")),
            )
        )
    return hits


def parse_open_library_search(body: object, locale: str | None = None) -> list[BookHit]:
    hits: list[BookHit] = []
    docs = body.get("docs") if isinstance(body, dict) else None
    for doc in docs if isinstance(docs, list) else []:
        if not isinstance(doc, dict):
            continue
        title = _text(doc.get("title"), 200)
        if title is None:
            continue
        authors = [name for name in doc.get("author_name") or [] if isinstance(name, str)]
        languages = doc.get("language")
        cover_id = doc.get("cover_i")
        hits.append(
            BookHit(
                title=title,
                author=_text(", ".join(authors), 120),
                year=_year(doc.get("first_publish_year")),
                isbn=_best_isbn(doc.get("isbn"), _isbn_groups(locale)),
                language=(
                    _language(languages[0])
                    if isinstance(languages, list) and len(languages) == 1
                    else None
                ),
                cover_url=(
                    OPEN_LIBRARY_COVER_ID_URL.format(cover_id=cover_id)
                    if isinstance(cover_id, int)
                    else None
                ),
            )
        )
    return hits


# --- the client -----------------------------------------------------------------------------


class BookLookup:
    """Looks books up by ISBN. Tests give it an ``httpx2.Client`` with a mock transport."""

    def __init__(self, client: httpx2.Client, google_api_key: str | None = None) -> None:
        self._client = client
        self._google_api_key = google_api_key

    @classmethod
    def create(cls, google_api_key: str | None = None) -> BookLookup:
        client = httpx2.Client(
            timeout=TIMEOUT_SECONDS,
            follow_redirects=True,
            headers={"User-Agent": "FriendsApp/1 (book lookup)"},
        )
        return cls(client, google_api_key)

    def close(self) -> None:
        self._client.close()

    def look_up(self, isbn: str) -> FoundBook | None:
        """What Google Books and Open Library know about ``isbn`` (an ISBN-13); None when
        neither knows it. Raises LookupUnavailable when neither could be asked."""
        google, google_failed = self._ask(self._google, isbn)
        if google is not None and all((google.description, google.language, google.cover_url)):
            return google
        library, library_failed = self._ask(self._open_library, isbn)
        if google is not None:
            return google.filled_from(library) if library else google
        if library is not None:
            return library
        if google_failed and library_failed:
            raise LookupUnavailable("Couldn't reach the book catalogues, try again later.")
        return None

    def search(self, query: str, *, locale: str | None = None) -> list[BookHit]:
        """Up to 10 books matching ``query`` (a title, an author or both): Google Books', or
        Open Library's when Google fails or finds nothing. Raises LookupUnavailable when
        neither could be asked."""
        google, google_failed = self._ask(self._google_search, query)
        if google:
            return google
        library, library_failed = self._ask(
            partial(self._open_library_search, locale=locale), query
        )
        if library:
            return library
        if google_failed and library_failed:
            raise LookupUnavailable("Couldn't reach the book catalogues, try again later.")
        return []

    def fetch_cover(self, isbn: str) -> tuple[bytes, str] | None:
        """A cover image for ``isbn`` as (bytes, content type), or None."""
        try:
            found = self.look_up(isbn)
        except LookupUnavailable:
            found = None  # Open Library's cover service may still answer
        urls = [OPEN_LIBRARY_COVER_URL.format(isbn=isbn)]
        if found is not None and found.cover_url:
            urls.insert(0, found.cover_url)
        for url in urls:
            image = self._download(url)
            if image is not None:
                return image
        return None

    # --- sources ---

    def _ask[T](self, source: Callable[[str], T], key: str) -> tuple[T | None, bool]:
        """(what ``source`` found for ``key``, whether asking it failed)."""
        try:
            found = source(key)
        except (httpx2.HTTPError, ValueError) as error:
            logger.warning(
                "book lookup via %s failed: %s", getattr(source, "func", source).__name__, error
            )
            return None, True
        return found, False

    def _google(self, isbn: str) -> FoundBook | None:
        params = {"q": f"isbn:{isbn}", "maxResults": "1"}
        if self._google_api_key:
            params["key"] = self._google_api_key
        response = self._client.get(GOOGLE_BOOKS_URL, params=params)
        response.raise_for_status()
        return parse_google(isbn, response.json())

    def _google_search(self, query: str) -> list[BookHit]:
        params = {"q": query, "maxResults": str(MAX_SEARCH_RESULTS), "printType": "books"}
        if self._google_api_key:
            params["key"] = self._google_api_key
        response = self._client.get(GOOGLE_BOOKS_URL, params=params)
        response.raise_for_status()
        return parse_google_search(response.json())[:MAX_SEARCH_RESULTS]

    def _open_library_search(self, query: str, locale: str | None) -> list[BookHit]:
        response = self._client.get(
            OPEN_LIBRARY_SEARCH_URL,
            params={
                "q": query,
                "limit": str(MAX_SEARCH_RESULTS),
                "fields": "title,author_name,first_publish_year,isbn,language,cover_i",
            },
        )
        response.raise_for_status()
        return parse_open_library_search(response.json(), locale)[:MAX_SEARCH_RESULTS]

    def _open_library(self, isbn: str) -> FoundBook | None:
        response = self._client.get(
            OPEN_LIBRARY_URL,
            params={"bibkeys": f"ISBN:{isbn}", "format": "json", "jscmd": "data"},
        )
        response.raise_for_status()
        data = response.json()
        if not isinstance(data, dict) or f"ISBN:{isbn}" not in data:
            return None
        # Best effort: the edition knows the language, its work the description.
        edition = self._json_or_none(f"{OPEN_LIBRARY_HOME}/isbn/{isbn}.json")
        work = None
        works = (edition or {}).get("works") or []
        key = works[0].get("key") if works and isinstance(works[0], dict) else None
        if isinstance(key, str) and re.fullmatch(r"/works/OL\d+W", key):
            work = self._json_or_none(f"{OPEN_LIBRARY_HOME}{key}.json")
        return parse_open_library(isbn, data, edition, work)

    def _json_or_none(self, url: str) -> dict[str, Any] | None:
        try:
            response = self._client.get(url)
            response.raise_for_status()
            body = response.json()
        except httpx2.HTTPError, ValueError:
            return None
        return body if isinstance(body, dict) else None

    def _download(self, url: str) -> tuple[bytes, str] | None:
        if urlsplit(url).hostname not in COVER_HOSTS:
            return None
        try:
            response = self._client.get(
                url, params={"default": "false"} if "openlibrary" in url else None
            )
        except httpx2.HTTPError:
            return None
        if response.status_code != 200 or len(response.content) > MAX_COVER_BYTES:
            return None
        content_type = image_type(response.content)
        return (response.content, content_type) if content_type else None


def image_type(data: bytes) -> str | None:
    """The content type of a JPEG, PNG or WebP image, from its first bytes; None otherwise."""
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    return None
