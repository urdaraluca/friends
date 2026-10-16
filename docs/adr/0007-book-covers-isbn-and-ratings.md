# ADR 0007: Book covers, ISBN lookup and ratings

- **Status:** Accepted
- **Date:** 2026-10-16
- **Related:** [contract sections 17.3 and 17.5](../api/contract.md), [ADR 0006](0006-group-kinds-and-books.md).

## Context

Book clubs wanted adding a book to work the way second-hand apps do it: scan the barcode and
the details fill themselves in, with a picture of the book. They also wanted the genre and
language, to say whose book it is and who has it when adding it, and to rate the books they've
read.

## Decision

| Question | Decision | Why |
|---|---|---|
| Where covers live | A `book_covers` table (a BLOB per book), at most 2 MiB, JPEG/PNG/WebP checked by magic bytes | The nightly SQLite backup already has them, and the Pi needs no new volume or object store. Phones downsize photos to ~1200 px, so a shelf of 1000 books stays well under 1 GB. |
| Reading a cover | `GET /books/{id}/cover` with the normal sign-in; the app reads it through its API client | Covers are group content, so the same membership rule as everything else. No signed URLs to expire. |
| Where the lookup runs | On the server, `GET /books/isbn/{isbn}` | One place for the catalogue logic. No CORS on the web app, testable with a fake transport, and the key (if any) stays on the server. |
| Which catalogues | Google Books first, Open Library to fill the gaps or as the fallback | Google has the best descriptions and languages, but its anonymous quota is shared and often used up. Open Library is free and open, and its subjects are good enough to guess a genre. |
| A found cover | The app previews the catalogue's https URL; saving asks the server to fetch it (`POST /books/{id}/cover/isbn`) | The server only fetches from the catalogues' fixed hosts, never a URL a client sends (no SSRF), and the cover ends up stored like a photo. |
| Genre | A fixed `BookGenre` list, guessed from catalogue subjects by vote | Filterable and translatable. Free text would split "Fantasy" and "fantasy". The guess is a suggestion the form shows; members change it. |
| Language | ISO 639-1 code | Catalogues return codes; the app names them in the user's language. |
| Owner and holder on add | Any member can add a book for another member, and say who has it. Whoever added it (`books.added_by_id`) may edit it like its owner. | Matches real life ("I have Ana's copy"). The member who typed it in, and took the photo, can fix it and add the cover. |
| Ratings | 1 to 5 stars per member and book, no text, not in the feed; the owner may rate | Simple, and a rating isn't news. Reviews can come later on the same table. |

## Consequences

- Production should set `GOOGLE_BOOKS_API_KEY`; without it the lookup often falls back to Open
  Library, which knows fewer books and has fewer descriptions.
- The server makes outbound HTTPS requests (to `www.googleapis.com`, `books.google.com`,
  `openlibrary.org` and `covers.openlibrary.org`), so the Pi needs outbound internet for the lookup.
  Everything else works without it.
- Camera scanning runs on the device (the app's barcode scanner). The web app needs HTTPS (or
  localhost) for the camera, and typing the ISBN always works.
