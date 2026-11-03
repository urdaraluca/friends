"""A minimal iCalendar (RFC 5545) writer for the webcal feed: one VEVENT per occurrence.

Occurrences are expanded on the server rather than sent as RRULEs with exceptions, so what a
calendar app shows is exactly what ``GET /me/calendar`` returns, edits and cancellations
included.
"""

from collections.abc import Iterable, Mapping
from datetime import UTC, date, datetime, timedelta
from uuid import UUID

from friends_api.features.events.models import EventKind
from friends_api.features.events.schemas import Occurrence, OccurrenceSource

PRODID = "-//Friends//Calendar feed//EN"
UID_DOMAIN = "friends.calendar"
_LINE_OCTETS = 75


def escape_text(value: str) -> str:
    """TEXT value escaping (RFC 5545 section 3.3.11)."""
    return (
        value.replace("\\", "\\\\")
        .replace(";", r"\;")
        .replace(",", "\\,")
        .replace("\r\n", "\\n")
        .replace("\n", "\\n")
        .replace("\r", "\\n")
    )


def fold(line: str) -> str:
    """Folds a content line at 75 octets, never inside a UTF-8 sequence (section 3.1)."""
    parts: list[str] = []
    current, size = "", 0
    for char in line:
        width = len(char.encode())
        limit = _LINE_OCTETS if not parts else _LINE_OCTETS - 1  # the leading space counts
        if size + width > limit:
            parts.append(current)
            current, size = "", 0
        current += char
        size += width
    parts.append(current)
    return "\r\n ".join(parts)


def _utc(instant: datetime) -> str:
    return instant.astimezone(UTC).strftime("%Y%m%dT%H%M%SZ")


def _date(day: date) -> str:
    return day.strftime("%Y%m%d")


def _uid(occurrence: Occurrence) -> str:
    owner = (
        f"birthday-{occurrence.user_id}"
        if occurrence.source is OccurrenceSource.MEMBER_BIRTHDAY
        else str(occurrence.event_id)
    )
    return f"{owner}-{occurrence.occurrence_key}@{UID_DOMAIN}"


def _summary(occurrence: Occurrence) -> str:
    """Birthdays get a cake, the language-neutral stand-in for the app's "'s birthday"."""
    if occurrence.kind is EventKind.BIRTHDAY:
        return f"🎂 {occurrence.title}"
    return occurrence.title


def _vevent(occurrence: Occurrence, group_name: str | None, stamp: str) -> list[str]:
    lines = ["BEGIN:VEVENT", f"UID:{_uid(occurrence)}", f"DTSTAMP:{stamp}"]
    if occurrence.all_day:
        assert occurrence.start_date is not None  # noqa: S101 - all-day occurrences have dates
        end = occurrence.end_date or occurrence.start_date
        lines += [
            f"DTSTART;VALUE=DATE:{_date(occurrence.start_date)}",
            # DTEND is exclusive; the API's end_date is the last day.
            f"DTEND;VALUE=DATE:{_date(end + timedelta(days=1))}",
            "TRANSP:TRANSPARENT",
        ]
    else:
        assert occurrence.starts_at is not None  # noqa: S101 - timed occurrences have instants
        assert occurrence.ends_at is not None  # noqa: S101
        lines += [f"DTSTART:{_utc(occurrence.starts_at)}", f"DTEND:{_utc(occurrence.ends_at)}"]
    lines.append(f"SUMMARY:{escape_text(_summary(occurrence))}")
    if group_name:
        lines.append(f"DESCRIPTION:{escape_text(group_name)}")
        lines.append(f"CATEGORIES:{escape_text(group_name)}")
    lines.append("END:VEVENT")
    return lines


def render(
    occurrences: Iterable[Occurrence],
    group_names: Mapping[UUID, str],
    *,
    calendar_name: str,
    now: datetime,
) -> str:
    """The whole VCALENDAR, with CRLF line endings."""
    stamp = _utc(now)
    lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        f"PRODID:{PRODID}",
        "CALSCALE:GREGORIAN",
        "METHOD:PUBLISH",
        f"X-WR-CALNAME:{escape_text(calendar_name)}",
        "X-PUBLISHED-TTL:PT1H",
        "REFRESH-INTERVAL;VALUE=DURATION:PT1H",
    ]
    for occurrence in occurrences:
        group_name = group_names.get(occurrence.group_id) if occurrence.group_id else None
        lines += _vevent(occurrence, group_name, stamp)
    lines.append("END:VCALENDAR")
    return "".join(fold(line) + "\r\n" for line in lines)
