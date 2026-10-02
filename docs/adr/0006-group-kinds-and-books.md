# ADR 0006: Group kinds and the book archive

- **Status:** Accepted
- **Date:** 2026-10-02
- **Related:** [contract section 17](../api/contract.md).

## Context

Two kinds of group came up that the generic backlog doesn't serve well:
- **A movie night** keeps a library of movies, picks the next one and puts it on the calendar.
- **A book club** has a shared shelf: each member adds the books they own, and others borrow them
  in turn. It also meets regularly.

Most of the movie night already exists: the Movie night category and its fields, "Schedule it",
and "I'm interested". The same goes for the club's meetings, which are recurring events with
single-occurrence edits. What's missing is a way to say what a group is for, and a place for
physical books changing hands.

## Decision

| Question | Decision | Why |
|---|---|---|
| What makes a movie night group | `groups.kind`: `general`, `movie_night` or `book_club`. It picks the seeded categories and the app's tabs. | A small, explicit choice at creation. The kind only shapes the app; the API restricts nothing by it, so a group can change its mind. |
| Prioritizing movies | Votes: the existing "I'm interested" count. A movie night's backlog sorts by it by default. | No new field to keep in sync. The group's interest already says what people want. A ranked list or priority levels were the alternatives. |
| Books: activities or their own table | Their own `books` table | A book is a thing someone owns, not a plan. It has an owner, a holder and a queue, and no status, cost or date. The backlog's Book club category stays for books to read **together**. |
| Lending | A queue (first come, first served) plus a one-tap handover by the owner or the holder | Friends trust each other. A request-and-approve flow would add steps without adding safety. |
| Who may get it | Any member, not only the head of the queue | Real life skips the queue sometimes. The app offers the first in line. |
| Leaving | The leaver's books leave with them. Books they hold count as returned, and they leave every queue. | The archive lists books members can lend. A book whose owner isn't in the group can't be lent. |
| Meetings | Plain recurring events, with no link to a book | Asked for as they are. A link can come later without changing books. |
| Feed | `book.added`, `book.lent` (with the recipient's name then) and `book.returned` | The moments members care about. Edits and queue changes would be noise. |

## Consequences

- `GET /groups/{id}/books` returns the whole archive with no paging, capped at 1000 books per group.
  The app filters it (available, mine, waiting) on the device.
- Changing a group's kind later doesn't add or remove categories. The categories screen still lets
  admins add a Book club or Movie night category to any group.
- A new general group gets eight default categories, Book club included.
