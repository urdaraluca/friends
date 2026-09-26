"""Recurrence and birthdays (contract section 5).

Pure functions with no database or FastAPI imports, so the future notification scheduler can
reuse them:

- :func:`canonicalize_rrule` validates a rule against the allowed subset (section 5.2, steps
  in order: the first failure's reason wins) and returns its canonical form;
- :func:`expand` lists the occurrences of a series in a calendar range (section 5.3);
- :func:`birthday_dates` places a yearly birthday (section 5.7);
- :func:`search_window` is the superset window stored on every event write (section 5.4);
- occurrence keys (section 5.6): :func:`instant_key`, :func:`date_key`,
  :func:`parse_occurrence_key`, :func:`is_occurrence`.

The client mirrors section 5.2 in ``rrule_spec.dart``; both are table-tested against
``docs/api/rrule_cases.json``.
"""

import calendar
import re
from collections.abc import Collection, Iterator
from dataclasses import dataclass
from datetime import MAXYEAR, UTC, date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from dateutil.rrule import rrulebase, rrulestr

MAX_OCCURRENCES = 1000
"""Per event per calendar request: a safety net, later occurrences are dropped."""
MIN_DATE = date(1000, 1, 1)
MAX_DATE = date(8999, 12, 31)
"""Supported dates for events and calendar ranges: far enough from years 1 and 9999 that the
search-window and expansion arithmetic (±14 h, 30 days, one period) never overflows."""
MAX_INTERVAL = 99
MAX_COUNT = 730
MAX_DURATION = timedelta(days=30)
FLOATING_MARGIN = timedelta(hours=14)
"""Floating dates (all-day events, birthdays) are widened by this much on both sides of their
search window, which covers every UTC offset (-12 h .. +14 h)."""

WEEKDAYS = ("MO", "TU", "WE", "TH", "FR", "SA", "SU")
FREQUENCIES = ("DAILY", "WEEKLY", "MONTHLY", "YEARLY")
PART_NAMES = ("FREQ", "INTERVAL", "BYDAY", "BYMONTHDAY", "COUNT", "UNTIL")

# EventKind values (the enum lives with the database models, which this module doesn't import).
ONE_TIME = "one_time"
RECURRING = "recurring"
BIRTHDAY = "birthday"

_ONE_DAY = timedelta(days=1)
_EXPANSION_MARGIN = timedelta(days=1)
"""dateutil compares datetimes of one zone by wall-clock time, which can be an hour off UTC
near a DST change; expanding with this margin and filtering on UTC instants afterwards keeps
the result exact."""

_INTERVAL = re.compile(r"[0-9]{1,3}")
_COUNT = re.compile(r"[0-9]{1,4}")
_MONTHLY_BYDAY = re.compile(r"(-1|[1-4])(MO|TU|WE|TH|FR|SA|SU)")
_BYMONTHDAY = re.compile(r"-?[0-9]{1,2}")
_UNTIL_TIMED = re.compile(r"([0-9]{4})([0-9]{2})([0-9]{2})T([0-9]{2})([0-9]{2})([0-9]{2})Z")
_UNTIL_DATE = re.compile(r"([0-9]{4})([0-9]{2})([0-9]{2})")
_LINE_BREAK = re.compile(r"[\n\r\v\f\x1c\x1d\x1e\x85\u2028\u2029]")


class InvalidRRule(ValueError):
    """The rule is outside the allowed subset. ``reason`` is a section 5.2 reason; the API
    returns it as ``errors[0].type`` of a 422 ``invalid_rrule``."""

    def __init__(self, reason: str, message: str) -> None:
        super().__init__(message)
        self.reason = reason
        self.message = message


# --- parsing, validation and canonical form (section 5.2) -------------------------------


def canonicalize_rrule(
    raw: str, start_local_date: date, all_day: bool, starts_at_utc: datetime | None = None
) -> str:
    """The canonical form of ``raw``, or :class:`InvalidRRule` with the first failing step's
    reason.

    ``start_local_date`` is the event's local start date (``starts_at`` in the event's zone for
    timed events, ``start_date`` for all-day ones); ``starts_at_utc`` is the start instant of a
    timed event (for ``UNTIL``). Only ``kind=recurring`` rules go through here: birthdays have
    their own fixed rule.

    Canonical form: ``FREQ;INTERVAL (omitted when 1);BYDAY;BYMONTHDAY;COUNT|UNTIL``, uppercase,
    weekly days sorted MO..SU, numbers without leading zeros, ``UNTIL`` as given. It is a fixed
    point: canonicalizing it again gives the same string.
    """
    # 1. Trim; no line breaks or DTSTART; strip an optional "RRULE:"; uppercase.
    text = raw.strip()
    if _LINE_BREAK.search(text) or "DTSTART" in text.upper():
        raise InvalidRRule("embedded_dtstart", "Send the rule only: no DTSTART and no line breaks.")
    if text[:6].upper() == "RRULE:":
        text = text[6:]
    text = text.upper()

    # 2-4. NAME=VALUE parts, checked left to right: syntax, supported name, no repeats.
    parts: dict[str, str] = {}
    for part in text.split(";"):
        name, equals, value = part.partition("=")
        if not equals or not name or not value:
            raise InvalidRRule("syntax", "Each part must be NAME=VALUE, separated by ';'.")
        if name not in PART_NAMES:
            raise InvalidRRule("unsupported_part", f"{name} is not supported.")
        if name in parts:
            raise InvalidRRule("duplicate_part", f"{name} appears more than once.")
        parts[name] = value

    # 5-6. FREQ.
    freq = parts.get("FREQ")
    if freq is None:
        raise InvalidRRule("missing_freq", "FREQ is required.")
    if freq not in FREQUENCIES:
        raise InvalidRRule("unsupported_freq", "FREQ must be DAILY, WEEKLY, MONTHLY or YEARLY.")

    # 7. INTERVAL.
    interval = 1
    if (raw_interval := parts.get("INTERVAL")) is not None:
        if not _INTERVAL.fullmatch(raw_interval) or not 1 <= int(raw_interval) <= MAX_INTERVAL:
            raise InvalidRRule(
                "interval_out_of_range", f"INTERVAL must be between 1 and {MAX_INTERVAL}."
            )
        interval = int(raw_interval)

    # 8. BYDAY.
    byday = parts.get("BYDAY")
    if byday is not None:
        byday = _canonical_byday(freq, byday)

    # 9. BYMONTHDAY.
    bymonthday: int | None = None
    if (raw_monthday := parts.get("BYMONTHDAY")) is not None:
        if freq != "MONTHLY" or byday is not None or not _BYMONTHDAY.fullmatch(raw_monthday):
            raise _bymonthday_invalid()
        bymonthday = int(raw_monthday)
        if not (1 <= bymonthday <= 28 or bymonthday == -1):
            raise _bymonthday_invalid()

    # 10. Defaults from the start.
    if freq == "WEEKLY" and byday is None:
        byday = WEEKDAYS[start_local_date.weekday()]
    if freq == "MONTHLY" and byday is None and bymonthday is None:
        if start_local_date.day > 28:
            raise InvalidRRule(
                "monthly_day_over_28",
                "A monthly rule starting after the 28th would skip short months; use "
                "BYMONTHDAY=-1 for the last day of the month.",
            )
        bymonthday = start_local_date.day

    # 11. No yearly rule from 29 February (it would skip three years out of four).
    if freq == "YEARLY" and (start_local_date.month, start_local_date.day) == (2, 29):
        raise InvalidRRule("yearly_feb29", "A yearly rule can't start on 29 February.")

    # 12-13. COUNT.
    count, until = parts.get("COUNT"), parts.get("UNTIL")
    if count is not None and until is not None:
        raise InvalidRRule("count_and_until", "Use COUNT or UNTIL, not both.")
    if count is not None:
        if not _COUNT.fullmatch(count) or not 1 <= int(count) <= MAX_COUNT:
            raise InvalidRRule("count_out_of_range", f"COUNT must be between 1 and {MAX_COUNT}.")
        count = str(int(count))

    # 14-15. UNTIL: the format for the event type, then not before the start.
    if until is not None:
        if all_day:
            if _parse_until_date(until) < start_local_date:
                raise _until_before_start()
        else:
            until_instant = _parse_until_instant(until)
            if starts_at_utc is None:
                raise ValueError("starts_at_utc is required for a timed rule with UNTIL")
            if until_instant < starts_at_utc:
                raise _until_before_start()

    canonical = [f"FREQ={freq}"]
    if interval != 1:
        canonical.append(f"INTERVAL={interval}")
    if byday is not None:
        canonical.append(f"BYDAY={byday}")
    if bymonthday is not None:
        canonical.append(f"BYMONTHDAY={bymonthday}")
    if count is not None:
        canonical.append(f"COUNT={count}")
    elif until is not None:
        canonical.append(f"UNTIL={until}")
    return ";".join(canonical)


def _canonical_byday(freq: str, value: str) -> str:
    if freq == "WEEKLY":
        days = value.split(",")
        if not all(day in WEEKDAYS for day in days) or len(set(days)) != len(days):
            raise _byday_invalid("Weekly BYDAY is a list of distinct days (MO..SU).")
        return ",".join(sorted(days, key=WEEKDAYS.index))
    if freq == "MONTHLY":
        if not _MONTHLY_BYDAY.fullmatch(value):
            raise _byday_invalid(
                "Monthly BYDAY is one ordinal weekday: 1 to 4 or -1, e.g. 2TU or -1FR."
            )
        return value
    raise _byday_invalid("BYDAY is only allowed with WEEKLY or MONTHLY.")


def _byday_invalid(message: str) -> InvalidRRule:
    return InvalidRRule("byday_invalid", message)


def _bymonthday_invalid() -> InvalidRRule:
    return InvalidRRule(
        "bymonthday_invalid",
        "BYMONTHDAY is monthly only: one day from 1 to 28 or -1 (the last day), without BYDAY.",
    )


def _until_before_start() -> InvalidRRule:
    return InvalidRRule("until_before_start", "UNTIL is before the start.")


def _until_format(all_day: bool) -> InvalidRRule:
    expected = "a date YYYYMMDD" if all_day else "a UTC date-time YYYYMMDDTHHMMSSZ"
    return InvalidRRule("until_format", f"UNTIL must be {expected}.")


def _parse_until_date(value: str) -> date:
    match = _UNTIL_DATE.fullmatch(value)
    if match is None:
        raise _until_format(all_day=True)
    try:
        return date(*(int(group) for group in match.groups()))
    except ValueError as exc:
        raise _until_format(all_day=True) from exc


def _parse_until_instant(value: str) -> datetime:
    match = _UNTIL_TIMED.fullmatch(value)
    if match is None:
        raise _until_format(all_day=False)
    year, month, day, hour, minute, second = (int(group) for group in match.groups())
    try:
        return datetime(year, month, day, hour, minute, second, tzinfo=UTC)
    except ValueError as exc:
        raise _until_format(all_day=False) from exc


@dataclass(frozen=True, slots=True)
class Rule:
    """The parts of a canonical rule that expansion needs."""

    freq: str
    interval: int = 1
    count: int | None = None
    until: str | None = None

    @classmethod
    def parse(cls, canonical: str) -> Rule:
        """Parses a *canonical* (stored) rule; it is trusted, not validated again."""
        parts = dict(part.split("=", 1) for part in canonical.split(";"))
        count = parts.get("COUNT")
        return cls(
            freq=parts["FREQ"],
            interval=int(parts.get("INTERVAL", "1")),
            count=int(count) if count is not None else None,
            until=parts.get("UNTIL"),
        )


# --- series, occurrences and keys ---------------------------------------------------------


@dataclass(frozen=True, slots=True, kw_only=True)
class Series:
    """What expansion needs from an event. Timed events have aware ``starts_at``/``ends_at``;
    all-day events and birthdays have ``start_date``/``end_date`` (inclusive)."""

    kind: str
    """``one_time``, ``recurring`` or ``birthday``."""
    all_day: bool
    starts_at: datetime | None = None
    ends_at: datetime | None = None
    start_date: date | None = None
    end_date: date | None = None
    timezone: str = "UTC"
    """The wall clock timed events are expanded in (IANA)."""
    rrule: str | None = None
    """Canonical; ``None`` for one-time events. Birthdays ignore it (section 5.7)."""

    @property
    def is_floating(self) -> bool:
        """All-day events and birthdays: the same calendar dates in every timezone."""
        return self.all_day or self.kind == BIRTHDAY

    @property
    def dates(self) -> tuple[date, date]:
        """``(start_date, end_date)`` of the first occurrence of a floating series."""
        if self.start_date is None:
            raise ValueError("an all-day series needs start_date")
        return self.start_date, self.end_date or self.start_date

    @property
    def instants(self) -> tuple[datetime, datetime]:
        """``(starts_at, ends_at)`` of the first occurrence of a timed series, in UTC."""
        if self.starts_at is None or self.ends_at is None:
            raise ValueError("a timed series needs starts_at and ends_at")
        return self.starts_at.astimezone(UTC), self.ends_at.astimezone(UTC)


@dataclass(frozen=True, slots=True, kw_only=True)
class Span:
    """One occurrence of a series."""

    key: str
    """``YYYYMMDDTHHMMSSZ`` (timed: the scheduled start in UTC) or ``YYYYMMDD``."""
    all_day: bool
    starts_at: datetime | None = None
    """Timed: the start instant (UTC)."""
    ends_at: datetime | None = None
    start_date: date | None = None
    """All-day: the first day."""
    end_date: date | None = None
    """All-day: the last day (inclusive)."""
    wall_start: datetime | None = None
    """Timed: the nominal wall-clock start the rule generated (naive, in the event's zone).
    Inside a spring-forward gap it doesn't exist; ``starts_at`` shows how it resolved."""


@dataclass(frozen=True, slots=True)
class Range:
    """A calendar range: the dates ``[from_date, to_date)``, and the same range as UTC instants
    (``from_date 00:00`` and ``to_date 00:00`` in the viewer's zone)."""

    from_date: date
    to_date: date
    start: datetime
    end: datetime

    @classmethod
    def in_zone(cls, from_date: date, to_date: date, tz: str) -> Range:
        zone = ZoneInfo(tz)
        return cls(
            from_date,
            to_date,
            datetime.combine(from_date, time(), zone).astimezone(UTC),
            datetime.combine(to_date, time(), zone).astimezone(UTC),
        )


def date_key(day: date) -> str:
    return f"{day.year:04d}{day.month:02d}{day.day:02d}"


def instant_key(instant: datetime) -> str:
    utc = instant.astimezone(UTC)
    return f"{date_key(utc)}T{utc.hour:02d}{utc.minute:02d}{utc.second:02d}Z"


_KEY = re.compile(r"([0-9]{4})([0-9]{2})([0-9]{2})(?:T([0-9]{2})([0-9]{2})([0-9]{2})Z)?")


def parse_occurrence_key(key: str) -> date | datetime:
    """A date (``YYYYMMDD``) or a UTC instant (``YYYYMMDDTHHMMSSZ``); ``ValueError`` if the key
    is malformed or not a real date and time. (A ``datetime`` is a ``date``: check it first.)"""
    match = _KEY.fullmatch(key)
    if match is None:
        raise ValueError("expected YYYYMMDD or YYYYMMDDTHHMMSSZ")
    year, month, day, hour, minute, second = match.groups()
    if hour is None:
        return date(int(year), int(month), int(day))
    return datetime(
        int(year), int(month), int(day), int(hour), int(minute), int(second), tzinfo=UTC
    )


# --- expansion (section 5.3) -------------------------------------------------------------


def expand(
    series: Series,
    in_range: Range,
    *,
    cancelled: Collection[str] = (),
    limit: int = MAX_OCCURRENCES,
) -> list[Span]:
    """The occurrences in ``in_range``, in order, without cancelled keys, at most ``limit``.

    - Timed: included when ``start < range end`` and ``end > range start`` (overlap; a
      zero-length occurrence counts when it starts in the range).
    - All-day and birthdays: included when ``start_date < to`` and ``end_date >= from``.
    """
    if series.is_floating:
        spans = _floating_spans(series, in_range.from_date, in_range.to_date - _ONE_DAY)
    else:
        spans = (
            span
            for span in _timed_spans(series, in_range.start, in_range.end)
            if _overlaps(span, in_range)
        )
    result: list[Span] = []
    for span in spans:
        if span.key in cancelled:
            continue
        result.append(span)
        if len(result) >= limit:
            break
    return result


def _overlaps(span: Span, in_range: Range) -> bool:
    assert span.starts_at is not None  # noqa: S101 - a timed span
    assert span.ends_at is not None  # noqa: S101
    return span.starts_at < in_range.end and (
        span.ends_at > in_range.start or span.starts_at >= in_range.start
    )


def next_occurrence(
    series: Series, *, now: datetime, today: date, cancelled: Collection[str] = ()
) -> Span | None:
    """The first occurrence that hasn't ended, skipping cancelled keys: a timed one ends after
    ``now``, an all-day one on or after ``today`` (the date in the zone the caller uses)."""
    if series.is_floating:
        spans = _floating_spans(series, today, None)
    else:
        spans = (
            span
            for span in _timed_spans(series, now, None)
            if span.ends_at is not None and span.ends_at > now
        )
    return next((span for span in spans if span.key not in cancelled), None)


def is_occurrence(series: Series, key: str) -> bool:
    """Whether ``key`` is a real occurrence of the series: for timed events the rule yields
    exactly that instant; for all-day events and birthdays that date is an occurrence date."""
    try:
        parsed = parse_occurrence_key(key)
    except ValueError:
        return False
    if isinstance(parsed, datetime):
        if series.is_floating:
            return False
        second = timedelta(seconds=1)
        spans = _timed_spans(series, parsed - second, parsed + second)
    else:
        if not series.is_floating:
            return False
        spans = _floating_spans(series, parsed, parsed)
    return any(span.key == key for span in spans)


def _timed_spans(series: Series, after: datetime, before: datetime | None) -> Iterator[Span]:
    """Chronological occurrences: a superset of those overlapping ``[after, before]``
    (``before=None``: no end). Callers filter exactly."""
    starts_at, ends_at = series.instants
    duration = ends_at - starts_at
    zone = ZoneInfo(series.timezone)
    if series.kind != RECURRING or series.rrule is None:
        yield _timed_span(starts_at, duration, starts_at.astimezone(zone))
        return
    lower = (after - duration).astimezone(zone) - _EXPANSION_MARGIN
    upper = before.astimezone(zone) + _EXPANSION_MARGIN if before is not None else None
    for local in _rule(series.rrule, starts_at.astimezone(zone), lower).xafter(lower, inc=True):
        if upper is not None and local > upper:
            return
        # A wall time in a spring-forward gap resolves with fold=0 (the offset before the
        # change); an ambiguous autumn time is its first instance (dateutil sets fold=0).
        yield _timed_span(local.astimezone(UTC), duration, local)


def _timed_span(start: datetime, duration: timedelta, local: datetime) -> Span:
    return Span(
        key=instant_key(start),
        all_day=False,
        starts_at=start,
        ends_at=start + duration,
        wall_start=local.replace(tzinfo=None, fold=0),
    )


def _floating_spans(series: Series, after: date, before: date | None) -> Iterator[Span]:
    """Chronological occurrences with ``end_date >= after`` and ``start_date <= before``
    (``before=None``: no end)."""
    start_date, end_date = series.dates
    span = end_date - start_date
    starts: Iterator[date]
    if series.kind == BIRTHDAY:
        span = timedelta(0)
        starts = _birthdays(start_date.month, start_date.day, start_date.year, after)
    elif series.kind != RECURRING or series.rrule is None:
        starts = iter([start_date] if end_date >= after else [])
    else:
        lower = datetime.combine(after - span, time())
        rule = _rule(series.rrule, datetime.combine(start_date, time()), lower)
        starts = (local.date() for local in rule.xafter(lower, inc=True))
    for day in starts:
        if before is not None and day > before:
            return
        yield Span(key=date_key(day), all_day=True, start_date=day, end_date=day + span)


def _rule(canonical: str, dtstart: datetime, lower: datetime) -> rrulebase:
    """``rrulestr(canonical, dtstart=dtstart)``, started as late as possible without changing
    any occurrence from ``lower`` on (:func:`fast_forward`)."""
    rule: rrulebase = rrulestr(
        canonical, dtstart=fast_forward(Rule.parse(canonical), dtstart, lower)
    )
    return rule


def fast_forward(rule: Rule, dtstart: datetime, lower: datetime) -> datetime:
    """A later start for ``rule`` whose occurrences from ``lower`` on are exactly the
    original's, so expanding a series that started long ago doesn't walk every period since
    (a daily rule from year 1 otherwise takes over a second per request).

    The new start is the first day of a period (day, Monday-based week, month, year) that is a
    whole number of intervals after the original's, at the original wall-clock time, and at
    least one interval before ``lower``. From its second period on, a rule no longer depends on
    the start's day: canonical MONTHLY rules always carry BYDAY or BYMONTHDAY, WEEKLY rules
    always carry BYDAY, and YEARLY rules never start on 29 February. Rules with COUNT count from
    the real start, so they are left alone (they have at most 730 occurrences anyway).
    """
    if rule.count is not None or dtstart >= lower:
        return dtstart
    day, target, n = dtstart.date(), lower.date(), rule.interval
    if rule.freq == "DAILY":
        periods = (target - day).days // n - 1
        new_day = day + timedelta(days=max(periods, 0) * n)
    elif rule.freq == "WEEKLY":
        monday = day - timedelta(days=day.weekday())
        periods = (target - monday).days // 7 // n - 1
        new_day = monday + timedelta(weeks=max(periods, 0) * n)
    elif rule.freq == "MONTHLY":
        periods = ((target.year - day.year) * 12 + target.month - day.month) // n - 1
        month_index = day.year * 12 + day.month - 1 + max(periods, 0) * n
        new_day = date(month_index // 12, month_index % 12 + 1, 1)
    else:  # YEARLY
        periods = (target.year - day.year) // n - 1
        if (day.month, day.day) == (2, 29):
            periods = 0  # not for a canonical rule (yearly_feb29); stay exact anyway
        new_day = day.replace(year=day.year + max(periods, 0) * n)
    if periods <= 0:
        return dtstart
    return datetime.combine(new_day, dtstart.timetz())


# --- birthdays (section 5.7) -------------------------------------------------------------


def birthday_on(year: int, month: int, day: int) -> date:
    """The birthday in ``year``: 29 February falls on 28 February in non-leap years."""
    if (month, day) == (2, 29) and not calendar.isleap(year):
        return date(year, 2, 28)
    return date(year, month, day)


def _birthdays(month: int, day: int, first_year: int | None, after: date) -> Iterator[date]:
    """Every birthday on or after ``after`` (from ``first_year`` on), in order."""
    for year in range(max(after.year, first_year or 1), MAXYEAR + 1):
        birthday = birthday_on(year, month, day)
        if birthday >= after:
            yield birthday


def birthday_dates(
    month: int, day: int, first_year: int | None, from_date: date, to_date: date
) -> list[date]:
    """The birthdays with ``from_date <= date < to_date``, in years from ``first_year`` on
    (``None``: any year). Member birthdays have no first year; a ``birthday`` event's is the
    year of its ``start_date``. Birthdays never use ``rrule``."""
    result: list[date] = []
    for birthday in _birthdays(month, day, first_year, from_date):
        if birthday >= to_date:
            break
        result.append(birthday)
    return result


# --- search window (section 5.4) ---------------------------------------------------------


def search_window(series: Series) -> tuple[datetime, datetime | None]:
    """``(window_start, window_end)``: a superset of every occurrence, written on each event
    write (``window_end=None``: the series never ends). The calendar's SQL prefilter is
    ``window_start < range end AND (window_end IS NULL OR window_end > range start)``."""
    if series.is_floating:
        start_date, end_date = series.dates
        window_start = _utc_midnight(start_date) - FLOATING_MARGIN
        if series.kind == BIRTHDAY:
            return window_start, None
        last_day = _last_floating_day(series, start_date, end_date)
        if last_day is None:
            return window_start, None
        try:
            return window_start, _utc_midnight(last_day + _ONE_DAY) + FLOATING_MARGIN
        except OverflowError:  # past year 9999: no end is still a superset
            return window_start, None
    starts_at, ends_at = series.instants
    try:
        return starts_at, _last_timed_end(series, starts_at, ends_at)
    except OverflowError:
        return starts_at, None


def _last_floating_day(series: Series, start_date: date, end_date: date) -> date | None:
    """The last day of the last occurrence; ``None`` for an open-ended rule."""
    if series.kind != RECURRING or series.rrule is None:
        return end_date
    rule = Rule.parse(series.rrule)
    if rule.until is not None:
        last_start = _parse_until_date(rule.until)
    elif rule.count is not None:
        occurrences = list(rrulestr(series.rrule, dtstart=datetime.combine(start_date, time())))
        last_start = occurrences[-1].date() if occurrences else start_date
    else:
        return None
    return last_start + (end_date - start_date)


def _last_timed_end(series: Series, starts_at: datetime, ends_at: datetime) -> datetime | None:
    """The end of the last occurrence; ``None`` for an open-ended rule."""
    if series.kind != RECURRING or series.rrule is None:
        return ends_at
    rule = Rule.parse(series.rrule)
    if rule.until is not None:
        last_start = _parse_until_instant(rule.until)
    elif rule.count is not None:
        dtstart = starts_at.astimezone(ZoneInfo(series.timezone))
        occurrences = list(rrulestr(series.rrule, dtstart=dtstart))
        last_start = occurrences[-1].astimezone(UTC) if occurrences else starts_at
    else:
        return None
    return last_start + (ends_at - starts_at)


def _utc_midnight(day: date) -> datetime:
    return datetime.combine(day, time(), UTC)
