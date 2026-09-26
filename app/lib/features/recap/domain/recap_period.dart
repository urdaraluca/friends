import 'package:friends/core/api/generated/export.dart';
import 'package:intl/intl.dart';

/// The first day of [day]'s month or year, as a local date.
DateTime periodStart(RecapPeriod period, DateTime day) =>
    period == RecapPeriod.year
    ? DateTime(day.year)
    : DateTime(day.year, day.month);

/// The period [offset] periods after (or before) the one starting on
/// [start].
DateTime shiftPeriod(RecapPeriod period, DateTime start, int offset) =>
    period == RecapPeriod.year
    ? DateTime(start.year + offset)
    : DateTime(start.year, start.month + offset);

/// "October 2026" or "2026".
String periodLabel(RecapPeriod period, DateTime start) =>
    period == RecapPeriod.year
    ? '${start.year}'
    : DateFormat.yMMMM().format(start);

/// A recap worth a banner on [today]: last year's all January, else last
/// month's during a month's first week.
({RecapPeriod period, DateTime start})? recapBannerFor(DateTime today) {
  if (today.month == DateTime.january) {
    return (period: RecapPeriod.year, start: DateTime(today.year - 1));
  }
  if (today.day <= 7) {
    return (
      period: RecapPeriod.month,
      start: DateTime(today.year, today.month - 1),
    );
  }
  return null;
}
