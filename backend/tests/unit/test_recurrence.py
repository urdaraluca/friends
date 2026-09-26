"""The recurrence engine (contract section 5) against the shared fixtures
(``docs/api/rrule_cases.json``, section 5.9) and extra cases."""

import json
import random
from datetime import UTC, date, datetime, time, timedelta
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

import pytest
from dateutil.rrule import rrulestr

from friends_api.features.events.recurrence import (
    InvalidRRule,
    Range,
    Rule,
    Series,
    birthday_dates,
    canonicalize_rrule,
    date_key,
    expand,
    fast_forward,
    instant_key,
    is_occurrence,
    next_occurrence,
    parse_occurrence_key,
    search_window,
)

CASES: dict[str, Any] = json.loads(
    (Path(__file__).parents[3] / "docs" / "api" / "rrule_cases.json").read_text("utf-8")
)
BUCHAREST = ZoneInfo("Europe/Bucharest")


def utc(text: str) -> datetime:
    return datetime.fromisoformat(text).astimezone(UTC)


def local(text: str, tz: str = "Europe/Bucharest") -> datetime:
    return datetime.fromisoformat(text).replace(tzinfo=ZoneInfo(tz))


def canonicalize(case: dict[str, Any]) -> str:
    if case["all_day"]:
        start = date.fromisoformat(case["dtstart_local"])
        return canonicalize_rrule(case["input"], start, True)
    start_local = local(case["dtstart_local"], case["tz"])
    return canonicalize_rrule(case["input"], start_local.date(), False, start_local)


def timed(rrule: str | None, starts: datetime, duration: timedelta, tz: str) -> Series:
    return Series(
        kind="recurring" if rrule else "one_time",
        all_day=False,
        starts_at=starts.astimezone(UTC),
        ends_at=(starts + duration).astimezone(UTC),
        timezone=tz,
        rrule=rrule,
    )


def all_day(rrule: str | None, start: date, end: date | None = None) -> Series:
    return Series(
        kind="recurring" if rrule else "one_time",
        all_day=True,
        start_date=start,
        end_date=end or start,
        rrule=rrule,
    )


def birthday(start: date) -> Series:
    return Series(
        kind="birthday", all_day=True, start_date=start, end_date=start, rrule="FREQ=YEARLY"
    )


def days(from_date: str, to_date: str, tz: str = "UTC") -> Range:
    return Range.in_zone(date.fromisoformat(from_date), date.fromisoformat(to_date), tz)


# --- the shared fixtures --------------------------------------------------------------------


@pytest.mark.parametrize("case", CASES["valid"], ids=[case["id"] for case in CASES["valid"]])
def test_valid_cases_canonicalize(case: dict[str, Any]) -> None:
    canonical = canonicalize(case)

    assert canonical == case["canonical"]
    assert canonicalize({**case, "input": canonical}) == canonical  # a fixed point


@pytest.mark.parametrize("case", CASES["valid"], ids=[case["id"] for case in CASES["valid"]])
def test_valid_cases_expand(case: dict[str, Any]) -> None:
    """Start-in-range semantics with duration 0 (contract section 5.9)."""
    from_date, to_date = (date.fromisoformat(day) for day in case["range"])
    if case["all_day"]:
        series = all_day(case["canonical"], date.fromisoformat(case["dtstart_local"]))
        spans = expand(series, Range.in_zone(from_date, to_date, case["tz"]))

        assert [span.start_date.isoformat() for span in spans if span.start_date] == case[
            "expected_local"
        ]
        return
    series = timed(
        case["canonical"], local(case["dtstart_local"], case["tz"]), timedelta(0), case["tz"]
    )
    spans = expand(series, Range.in_zone(from_date, to_date, case["tz"]))

    assert [span.wall_start.isoformat() for span in spans if span.wall_start] == case[
        "expected_local"
    ]
    assert [
        span.starts_at.isoformat().replace("+00:00", "Z") for span in spans if span.starts_at
    ] == case["expected_utc"]
    assert [span.key for span in spans] == [
        instant_key(utc(text.replace("Z", "+00:00"))) for text in case["expected_utc"]
    ]


@pytest.mark.parametrize(
    "case", CASES["invalid"], ids=[f"{c['reason']}:{c['input']!r}" for c in CASES["invalid"]]
)
def test_invalid_cases_are_rejected_with_their_reason(case: dict[str, Any]) -> None:
    start = date.fromisoformat(case["start_date"])
    starts_at = None if case["all_day"] else datetime.combine(start, time(19), BUCHAREST)

    with pytest.raises(InvalidRRule) as caught:
        canonicalize_rrule(case["input"], start, case["all_day"], starts_at)

    assert caught.value.reason == case["reason"]
    assert caught.value.message


@pytest.mark.parametrize("case", CASES["birthdays"])
def test_birthday_cases(case: dict[str, Any]) -> None:
    from_date, to_date = (date.fromisoformat(day) for day in case["range"])
    first_year = date.fromisoformat(case["start_date"]).year if case["start_date"] else None

    dates = birthday_dates(case["month"], case["day"], first_year, from_date, to_date)

    assert [day.isoformat() for day in dates] == case["expected"]
    if case["start_date"]:  # the same through a birthday event
        series = birthday(date.fromisoformat(case["start_date"]))
        spans = expand(series, Range.in_zone(from_date, to_date, "UTC"))
        assert [span.start_date.isoformat() for span in spans if span.start_date] == case[
            "expected"
        ]


def test_the_fixtures_cover_every_reason() -> None:
    reasons = {case["reason"] for case in CASES["invalid"]}

    assert len(CASES["valid"]) == 20
    assert len(CASES["invalid"]) == 33
    assert len(CASES["birthdays"]) == 4
    assert reasons == {
        "embedded_dtstart",
        "syntax",
        "unsupported_part",
        "duplicate_part",
        "missing_freq",
        "unsupported_freq",
        "interval_out_of_range",
        "byday_invalid",
        "bymonthday_invalid",
        "monthly_day_over_28",
        "yearly_feb29",
        "count_and_until",
        "count_out_of_range",
        "until_format",
        "until_before_start",
    }


# --- canonical form: more cases ------------------------------------------------------------


@pytest.mark.parametrize(
    ("raw", "canonical"),
    [
        ("  FREQ=WEEKLY;INTERVAL=02;BYDAY=SU,MO  ", "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,SU"),
        ("RRULE:FREQ=DAILY;COUNT=007", "FREQ=DAILY;COUNT=7"),
        ("rrule:FREQ=monthly;bymonthday=-01", "FREQ=MONTHLY;BYMONTHDAY=-1"),
        ("FREQ=MONTHLY;BYMONTHDAY=05;INTERVAL=3", "FREQ=MONTHLY;INTERVAL=3;BYMONTHDAY=5"),
        ("COUNT=3;FREQ=YEARLY;INTERVAL=1", "FREQ=YEARLY;COUNT=3"),
        ("FREQ=WEEKLY", "FREQ=WEEKLY;BYDAY=TH"),  # 2026-10-01 is a Thursday
        ("FREQ=MONTHLY", "FREQ=MONTHLY;BYMONTHDAY=1"),
        ("FREQ=DAILY;UNTIL=20261231t235959z", "FREQ=DAILY;UNTIL=20261231T235959Z"),
        ("FREQ=WEEKLY;BYDAY=FR,MO,WE,SU,TU,TH,SA", "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR,SA,SU"),
    ],
)
def test_canonical_form(raw: str, canonical: str) -> None:
    start = datetime(2026, 10, 1, 19, tzinfo=BUCHAREST)

    assert canonicalize_rrule(raw, start.date(), False, start) == canonical
    assert canonicalize_rrule(canonical, start.date(), False, start) == canonical


@pytest.mark.parametrize(
    ("raw", "reason"),
    [
        ("", "syntax"),
        ("FREQ=WEEKLY;", "syntax"),
        ("FREQ", "syntax"),
        ("=WEEKLY", "syntax"),
        ("  ", "syntax"),  # blank after trimming
        ("FREQ=DAILY\nCOUNT=2", "embedded_dtstart"),
        ("freq=daily;dtstart=20261001", "embedded_dtstart"),
        ("FREQ=MONTHLY;BYDAY=-1FR;BYSETPOS=-1", "unsupported_part"),
        ("BYHOUR=9;FREQ", "unsupported_part"),  # parts are checked left to right
        ("FREQ=DAILY;FREQ=DAILY;BYHOUR=1", "duplicate_part"),
        ("FREQ=SECONDLY", "unsupported_freq"),
        ("FREQ=DAILY;INTERVAL=abc", "interval_out_of_range"),
        ("FREQ=DAILY;INTERVAL=0099", "interval_out_of_range"),  # at most 3 digits
        ("FREQ=WEEKLY;BYDAY=MO,", "byday_invalid"),
        ("FREQ=WEEKLY;BYDAY=XX", "byday_invalid"),
        ("FREQ=MONTHLY;BYDAY=-2FR", "byday_invalid"),
        ("FREQ=MONTHLY;BYDAY=+1FR", "byday_invalid"),
        ("FREQ=YEARLY;BYDAY=MO", "byday_invalid"),
        ("FREQ=MONTHLY;BYMONTHDAY=0", "bymonthday_invalid"),
        ("FREQ=MONTHLY;BYMONTHDAY=-2", "bymonthday_invalid"),
        ("FREQ=DAILY;BYMONTHDAY=3", "bymonthday_invalid"),
        ("FREQ=DAILY;COUNT=12345", "count_out_of_range"),
        ("FREQ=DAILY;COUNT=x", "count_out_of_range"),
        ("FREQ=DAILY;UNTIL=20261332T000000Z", "until_format"),
        ("FREQ=DAILY;UNTIL=2026-12-31", "until_format"),
        ("FREQ=DAILY;UNTIL=20261001T155959Z", "until_before_start"),
    ],
)
def test_more_invalid_rules(raw: str, reason: str) -> None:
    start = datetime(2026, 10, 1, 19, tzinfo=BUCHAREST)  # 16:00Z

    with pytest.raises(InvalidRRule) as caught:
        canonicalize_rrule(raw, start.date(), False, start)

    assert caught.value.reason == reason


def test_the_first_failing_step_wins() -> None:
    start = date(2026, 10, 31)
    # Each rule has two defects; the earlier step's reason is reported.
    cases = {
        "FREQ=HOURLY;INTERVAL=0": "unsupported_freq",
        "FREQ=MONTHLY;INTERVAL=100;BYDAY=5FR": "interval_out_of_range",
        "FREQ=MONTHLY;BYDAY=5FR;BYMONTHDAY=40": "byday_invalid",
        "FREQ=MONTHLY;COUNT=0": "monthly_day_over_28",
        "FREQ=DAILY;COUNT=0;UNTIL=2020": "count_and_until",
        "FREQ=DAILY;COUNT=0;BYSETPOS=1": "unsupported_part",
    }
    for raw, reason in cases.items():
        with pytest.raises(InvalidRRule) as caught:
            canonicalize_rrule(raw, start, True)
        assert caught.value.reason == reason, raw


def test_all_day_until_is_a_date_and_may_equal_the_start() -> None:
    start = date(2026, 10, 3)

    assert (
        canonicalize_rrule("FREQ=WEEKLY;UNTIL=20261003", start, True)
        == "FREQ=WEEKLY;BYDAY=SA;UNTIL=20261003"
    )
    with pytest.raises(InvalidRRule) as caught:
        canonicalize_rrule("FREQ=WEEKLY;UNTIL=20261002", start, True)
    assert caught.value.reason == "until_before_start"
    with pytest.raises(InvalidRRule) as caught:
        canonicalize_rrule("FREQ=WEEKLY;UNTIL=20260230", start, True)
    assert caught.value.reason == "until_format"


def test_a_timed_rule_with_until_needs_the_start_instant() -> None:
    with pytest.raises(ValueError, match="starts_at_utc"):
        canonicalize_rrule("FREQ=DAILY;UNTIL=20261231T000000Z", date(2026, 10, 1), False)


# --- expansion: more cases -----------------------------------------------------------------


def test_weekly_thursday_keeps_its_wall_time_across_the_dst_end() -> None:
    series = timed(
        "FREQ=WEEKLY;BYDAY=TH", local("2026-10-01T19:00"), timedelta(hours=3), "Europe/Bucharest"
    )

    spans = expand(series, days("2026-10-20", "2026-11-01", "Europe/Bucharest"))

    assert [(span.starts_at, span.ends_at) for span in spans] == [
        (utc("2026-10-22T16:00Z"), utc("2026-10-22T19:00Z")),
        (utc("2026-10-29T17:00Z"), utc("2026-10-29T20:00Z")),
    ]
    assert [span.key for span in spans] == ["20261022T160000Z", "20261029T170000Z"]


def test_last_friday_and_last_day_of_the_month() -> None:
    last_friday = timed(
        "FREQ=MONTHLY;BYDAY=-1FR", local("2026-10-30T20:00"), timedelta(hours=2), "Europe/Bucharest"
    )
    last_day = all_day("FREQ=MONTHLY;BYMONTHDAY=-1", date(2027, 1, 31))

    fridays = expand(last_friday, days("2027-01-01", "2027-06-01", "Europe/Bucharest"))
    last_days = expand(last_day, days("2027-01-01", "2027-06-01"))

    assert [span.wall_start.date().isoformat() for span in fridays if span.wall_start] == [
        "2027-01-29",
        "2027-02-26",
        "2027-03-26",
        "2027-04-30",
        "2027-05-28",
    ]
    assert [span.key for span in last_days] == [
        "20270131",
        "20270228",
        "20270331",
        "20270430",
        "20270531",
    ]


def test_timed_occurrences_overlapping_the_range_start_are_included() -> None:
    # 23:00-01:00 local every day: the one from the evening before overlaps 00:00.
    series = timed("FREQ=DAILY", local("2026-10-01T23:00"), timedelta(hours=2), "Europe/Bucharest")

    spans = expand(series, days("2026-10-05", "2026-10-06", "Europe/Bucharest"))

    assert [span.wall_start.isoformat() for span in spans if span.wall_start] == [
        "2026-10-04T23:00:00",
        "2026-10-05T23:00:00",
    ]


def test_an_occurrence_ending_exactly_at_the_range_start_is_left_out() -> None:
    series = timed(None, local("2026-10-04T22:00"), timedelta(hours=2), "Europe/Bucharest")

    assert expand(series, days("2026-10-05", "2026-10-06", "Europe/Bucharest")) == []
    assert len(expand(series, days("2026-10-04", "2026-10-05", "Europe/Bucharest"))) == 1


def test_the_range_is_taken_in_the_viewers_zone() -> None:
    series = timed(
        None, local("2026-10-01T01:30"), timedelta(hours=1), "Europe/Bucharest"
    )  # 22:30Z

    assert expand(series, days("2026-09-30", "2026-10-01", "UTC"))
    assert not expand(series, days("2026-09-30", "2026-10-01", "Europe/Bucharest"))


def test_a_three_day_all_day_event_is_on_three_dates_for_every_viewer() -> None:
    series = all_day(None, date(2026, 10, 9), date(2026, 10, 11))
    for tz in ("Pacific/Honolulu", "UTC", "Europe/Bucharest", "Pacific/Kiritimati"):
        for day in range(8, 13):
            spans = expand(series, Range.in_zone(date(2026, 10, day), date(2026, 10, day + 1), tz))
            assert bool(spans) == (9 <= day <= 11), (tz, day)


def test_recurring_all_day_spans_cover_their_days() -> None:
    weekend = all_day("FREQ=WEEKLY;BYDAY=FR", date(2026, 10, 2), date(2026, 10, 4))

    spans = expand(weekend, days("2026-10-11", "2026-10-12"))  # a Sunday

    assert [(span.key, span.start_date, span.end_date) for span in spans] == [
        ("20261009", date(2026, 10, 9), date(2026, 10, 11))
    ]


def test_cancelled_keys_are_dropped() -> None:
    series = timed(
        "FREQ=WEEKLY;BYDAY=TH", local("2026-10-01T19:00"), timedelta(hours=1), "Europe/Bucharest"
    )

    spans = expand(series, days("2026-10-01", "2026-10-16"), cancelled={"20261008T160000Z"})

    assert [span.key for span in spans] == ["20261001T160000Z", "20261015T160000Z"]


def test_at_most_limit_occurrences() -> None:
    series = timed("FREQ=DAILY", local("2026-01-01T09:00"), timedelta(hours=1), "UTC")

    assert len(expand(series, days("2026-01-01", "2027-02-01"))) == 396
    assert len(expand(series, days("2026-01-01", "2027-02-01"), limit=10)) == 10


def test_one_time_events_have_exactly_one_occurrence() -> None:
    series = timed(None, local("2026-10-01T19:00"), timedelta(hours=2), "Europe/Bucharest")
    trip = all_day(None, date(2026, 10, 9), date(2026, 10, 11))

    assert [span.key for span in expand(series, days("2026-01-01", "2027-01-01"))] == [
        "20261001T160000Z"
    ]
    assert [span.key for span in expand(trip, days("2026-01-01", "2027-01-01"))] == ["20261009"]
    assert expand(trip, days("2026-10-12", "2027-01-01")) == []


def test_a_29_february_birthday_event() -> None:
    series = birthday(date(2028, 2, 29))

    spans = expand(series, days("2026-01-01", "2031-01-01"))

    assert [span.key for span in spans] == ["20280229", "20290228", "20300228"]
    assert birthday_dates(2, 29, None, date(2027, 1, 1), date(2029, 1, 1)) == [
        date(2027, 2, 28),
        date(2028, 2, 29),
    ]


def test_a_rule_started_long_ago_expands_quickly_and_exactly() -> None:
    series = timed("FREQ=DAILY", datetime(1, 1, 3, 19, tzinfo=UTC), timedelta(hours=1), "UTC")

    spans = expand(series, days("2026-10-01", "2026-10-04"))

    assert [span.key for span in spans] == [
        "20261001T190000Z",
        "20261002T190000Z",
        "20261003T190000Z",
    ]


@pytest.mark.parametrize("seed", range(40))
def test_fast_forward_never_changes_an_occurrence(seed: int) -> None:
    """Expanding from the fast-forwarded start gives exactly the original occurrences."""
    rng = random.Random(seed)
    freq = rng.choice(["DAILY", "WEEKLY", "MONTHLY", "YEARLY"])
    interval = rng.choice([1, 1, 2, 3, 5, 7, 12])
    extra = {
        "DAILY": [""],
        "WEEKLY": [";BYDAY=MO", ";BYDAY=TU,SA", ";BYDAY=SU", ";BYDAY=MO,WE,FR,SU"],
        "MONTHLY": [";BYDAY=-1FR", ";BYDAY=2TU", ";BYMONTHDAY=-1", ";BYMONTHDAY=13"],
        "YEARLY": [""],
    }[freq]
    canonical = f"FREQ={freq}" + (f";INTERVAL={interval}" if interval > 1 else "")
    canonical += rng.choice(extra)
    zone = ZoneInfo(rng.choice(["UTC", "Europe/Bucharest", "America/New_York"]))
    start_day = date(2019, 1, 1) + timedelta(days=rng.randrange(1500))
    if (start_day.month, start_day.day) == (2, 29):
        start_day += timedelta(days=1)
    dtstart = datetime.combine(start_day, time(rng.randrange(24), rng.choice([0, 30])), zone)
    lower = dtstart + timedelta(days=rng.randrange(30, 2500))
    upper = lower + timedelta(days=120)

    moved = fast_forward(Rule.parse(canonical), dtstart, lower)

    assert moved <= lower
    original = rrulestr(canonical, dtstart=dtstart).between(lower, upper, inc=True)
    assert rrulestr(canonical, dtstart=moved).between(lower, upper, inc=True) == original


def test_fast_forward_leaves_count_rules_alone() -> None:
    start = datetime(2020, 1, 1, 9, tzinfo=UTC)
    later = datetime(2026, 1, 1, tzinfo=UTC)

    assert fast_forward(Rule.parse("FREQ=DAILY;COUNT=700"), start, later) == start
    assert fast_forward(Rule.parse("FREQ=DAILY"), start, start) == start
    assert fast_forward(Rule.parse("FREQ=YEARLY"), start, later).year == 2025


# --- next occurrence -----------------------------------------------------------------------


def test_next_timed_occurrence_is_the_first_that_has_not_ended() -> None:
    series = timed(
        "FREQ=WEEKLY;BYDAY=TH", local("2026-10-01T19:00"), timedelta(hours=3), "Europe/Bucharest"
    )
    running = utc("2026-10-08T17:00Z")  # the 8 October one is in progress

    span = next_occurrence(series, now=running, today=running.date())
    after = next_occurrence(series, now=utc("2026-10-08T19:00Z"), today=running.date())
    skipping = next_occurrence(
        series, now=running, today=running.date(), cancelled={"20261008T160000Z"}
    )

    assert span is not None

    assert span.key == "20261008T160000Z"
    assert after is not None
    assert after.key == "20261015T160000Z"
    assert skipping is not None
    assert skipping.key == "20261015T160000Z"


def test_next_occurrence_of_ended_and_one_time_series() -> None:
    now = utc("2026-10-10T12:00Z")
    past = timed("FREQ=DAILY;COUNT=3", local("2026-10-01T09:00"), timedelta(hours=1), "UTC")
    one_time = timed(None, local("2026-10-20T09:00"), timedelta(hours=1), "UTC")
    trip = all_day(None, date(2026, 10, 8), date(2026, 10, 10))

    assert next_occurrence(past, now=now, today=now.date()) is None
    assert next_occurrence(one_time, now=now, today=now.date()) is not None
    span = next_occurrence(trip, now=now, today=date(2026, 10, 10))  # its last day
    assert span is not None
    assert span.key == "20261008"
    assert next_occurrence(trip, now=now, today=date(2026, 10, 11)) is None


def test_next_birthday_and_all_day_occurrences() -> None:
    today = date(2027, 3, 1)
    now = datetime.combine(today, time(), UTC)

    feb29 = next_occurrence(birthday(date(2028, 2, 29)), now=now, today=today)
    yearly = next_occurrence(all_day("FREQ=YEARLY", date(2020, 3, 1)), now=now, today=today)
    skipped = next_occurrence(
        all_day("FREQ=YEARLY", date(2020, 3, 1)), now=now, today=today, cancelled={"20270301"}
    )

    assert feb29 is not None

    assert feb29.key == "20280229"
    assert yearly is not None
    assert yearly.key == "20270301"
    assert skipped is not None
    assert skipped.key == "20280301"


# --- keys ----------------------------------------------------------------------------------


def test_keys() -> None:
    assert date_key(date(2026, 10, 1)) == "20261001"
    assert instant_key(local("2026-10-29T19:00")) == "20261029T170000Z"
    assert parse_occurrence_key("20261001") == date(2026, 10, 1)
    assert parse_occurrence_key("20261029T170000Z") == utc("2026-10-29T17:00Z")
    for malformed in ("2026-10-01", "20261301", "20261001T250000Z", "20261001T170000", "x"):
        with pytest.raises(ValueError):  # noqa: PT011 - any ValueError
            parse_occurrence_key(malformed)


def test_is_occurrence() -> None:
    weekly = timed(
        "FREQ=WEEKLY;BYDAY=TH", local("2026-10-01T19:00"), timedelta(hours=1), "Europe/Bucharest"
    )
    trip = all_day("FREQ=MONTHLY;BYMONTHDAY=1", date(2026, 10, 1), date(2026, 10, 3))

    assert is_occurrence(weekly, "20261029T170000Z")
    assert not is_occurrence(weekly, "20261029T160000Z")  # the wall time moved with DST
    assert not is_occurrence(weekly, "20260924T160000Z")  # before the start
    assert not is_occurrence(weekly, "20261029")  # a date key on a timed event
    assert not is_occurrence(weekly, "bogus")
    assert is_occurrence(trip, "20261101")
    assert not is_occurrence(trip, "20261102")  # inside an occurrence, not its first day
    assert not is_occurrence(trip, "20261101T000000Z")
    assert is_occurrence(birthday(date(2028, 2, 29)), "20290228")
    assert not is_occurrence(birthday(date(2028, 2, 29)), "20270228")  # before its first year


# --- search window -------------------------------------------------------------------------


def test_search_window_of_timed_events() -> None:
    starts = local("2026-10-01T19:00")
    hour = timedelta(hours=1)

    assert search_window(timed(None, starts, hour, "Europe/Bucharest")) == (
        utc("2026-10-01T16:00Z"),
        utc("2026-10-01T17:00Z"),
    )
    assert search_window(timed("FREQ=WEEKLY;BYDAY=TH", starts, hour, "Europe/Bucharest")) == (
        utc("2026-10-01T16:00Z"),
        None,
    )
    assert search_window(
        timed("FREQ=WEEKLY;BYDAY=TH;COUNT=5", starts, hour, "Europe/Bucharest")
    ) == (utc("2026-10-01T16:00Z"), utc("2026-10-29T18:00Z"))
    assert search_window(
        timed("FREQ=DAILY;UNTIL=20261010T000000Z", starts, hour, "Europe/Bucharest")
    ) == (utc("2026-10-01T16:00Z"), utc("2026-10-10T01:00Z"))


def test_search_window_of_floating_events() -> None:
    margin = timedelta(hours=14)
    start = date(2026, 10, 9)
    midnight = datetime(2026, 10, 9, tzinfo=UTC)

    assert search_window(all_day(None, start, date(2026, 10, 11))) == (
        midnight - margin,
        datetime(2026, 10, 12, tzinfo=UTC) + margin,
    )
    assert search_window(all_day("FREQ=YEARLY", start)) == (midnight - margin, None)
    assert search_window(all_day("FREQ=DAILY;COUNT=3", start, date(2026, 10, 10))) == (
        midnight - margin,
        datetime(2026, 10, 13, tzinfo=UTC) + margin,
    )
    assert search_window(all_day("FREQ=DAILY;UNTIL=20261020", start, date(2026, 10, 10))) == (
        midnight - margin,
        datetime(2026, 10, 22, tzinfo=UTC) + margin,
    )
    assert search_window(birthday(start)) == (midnight - margin, None)


def test_search_windows_past_year_9999_are_open_ended() -> None:
    far = all_day("FREQ=DAILY;UNTIL=99991231", date(2026, 10, 9))
    timed_far = timed(
        "FREQ=DAILY;UNTIL=99991231T235959Z", local("2026-10-01T19:00"), timedelta(days=2), "UTC"
    )

    assert search_window(far)[1] is None
    assert search_window(timed_far)[1] is None


def test_every_occurrence_lies_in_the_search_window() -> None:
    series_list = [
        timed(
            "FREQ=MONTHLY;BYDAY=-1FR;COUNT=12",
            local("2026-10-30T20:00"),
            timedelta(hours=5),
            "Europe/Bucharest",
        ),
        timed(
            "FREQ=DAILY;UNTIL=20261231T000000Z",
            local("2026-10-01T23:30"),
            timedelta(hours=2),
            "Europe/Bucharest",
        ),
        all_day("FREQ=WEEKLY;BYDAY=SA;COUNT=10", date(2026, 10, 3), date(2026, 10, 4)),
        all_day("FREQ=MONTHLY;BYMONTHDAY=-1;UNTIL=20270331", date(2026, 10, 31), date(2026, 11, 2)),
    ]
    for series in series_list:
        window_start, window_end = search_window(series)
        assert window_end is not None
        spans = expand(series, days("2026-01-01", "2028-01-01"))
        assert spans
        for span in spans:
            if span.starts_at is not None and span.ends_at is not None:
                assert window_start <= span.starts_at
                assert span.ends_at <= window_end
            else:
                assert span.start_date is not None
                assert span.end_date is not None
                for tz in ("Pacific/Kiritimati", "Etc/GMT+12"):
                    zone = ZoneInfo(tz)
                    first = datetime.combine(span.start_date, time(), zone)
                    last = datetime.combine(span.end_date + timedelta(days=1), time(), zone)
                    assert window_start <= first
                    assert last <= window_end


def test_a_series_needs_its_timing_fields() -> None:
    with pytest.raises(ValueError, match="start_date"):
        search_window(Series(kind="one_time", all_day=True))
    with pytest.raises(ValueError, match="starts_at"):
        search_window(Series(kind="one_time", all_day=False))
