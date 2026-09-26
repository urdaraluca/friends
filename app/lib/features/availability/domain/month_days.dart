import 'package:friends/core/api/date_only.dart';

/// The days of [month]'s grid: the Monday on or before the 1st through the
/// Sunday on or after the last day, as local dates. Built with calendar
/// arithmetic, so DST changes can't shift a day.
List<DateTime> monthGridDays(DateTime month) {
  final first = DateTime(month.year, month.month);
  final last = DateTime(month.year, month.month + 1, 0);
  final start = DateTime(first.year, first.month, 1 - (first.weekday - 1));
  final end = DateTime(last.year, last.month, last.day + (7 - last.weekday));
  return [
    for (
      var day = start;
      !day.isAfter(end);
      day = DateTime(day.year, day.month, day.day + 1)
    )
      day,
  ];
}

/// The dates [month]'s grid shows, `[from, to)` as UTC midnights: what the
/// availability screens load and save (at most 42 days).
({DateTime from, DateTime to}) gridRange(DateTime month) {
  final days = monthGridDays(month);
  final last = days.last;
  return (
    from: DateOnly.from(days.first),
    to: DateOnly.of(last.year, last.month, last.day + 1),
  );
}
