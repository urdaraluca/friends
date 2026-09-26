import 'package:friends/core/api/date_only.dart';
import 'package:friends/core/api/generated/export.dart';

/// The occurrences of a calendar range by day, as the device shows them:
/// keys are `DateOnly` dates (UTC midnights).
///
/// - An all-day occurrence is on every day from `start_date` to `end_date`
///   (inclusive): floating dates, the same everywhere.
/// - A timed occurrence is on every device-local day it overlaps: one that
///   crosses midnight shows on both days; one ending exactly at midnight
///   doesn't spill into the next day.
///
/// Each day lists all-day occurrences first, then timed ones by start, then
/// by title (contract section 5.5).
class OccurrenceIndex {
  new(Iterable<Occurrence> occurrences) {
    for (final occurrence in occurrences) {
      for (final day in daysOf(occurrence)) {
        (_byDay[DateOnly.format(day)] ??= []).add(occurrence);
      }
    }
    for (final list in _byDay.values) {
      list.sort(_compare);
    }
  }

  final Map<String, List<Occurrence>> _byDay = {};

  /// The occurrences on [day] (any `DateTime`; only its date counts).
  List<Occurrence> on(DateTime day) =>
      _byDay[DateOnly.format(DateOnly.from(day))] ?? const [];

  /// The days (UTC midnights) [occurrence] is on in the device's zone.
  static List<DateTime> daysOf(Occurrence occurrence) {
    final DateTime first;
    final DateTime last;
    if (occurrence.allDay || occurrence.startsAt == null) {
      final start = occurrence.startDate;
      if (start == null) return const [];
      first = DateOnly.from(start);
      last = DateOnly.from(occurrence.endDate ?? start);
    } else {
      final start = occurrence.startsAt!.toLocal();
      final end = (occurrence.endsAt ?? occurrence.startsAt!).toLocal();
      first = DateOnly.from(start);
      // [start, end): the last moment is just before the end.
      final lastMoment = end.isAfter(start)
          ? end.subtract(const Duration(microseconds: 1))
          : start;
      last = DateOnly.from(lastMoment);
    }
    return [
      for (
        var day = first;
        !day.isAfter(last);
        day = day.add(const Duration(days: 1))
      )
        day,
    ];
  }

  static int _compare(Occurrence a, Occurrence b) {
    if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
    final aStart = a.startsAt;
    final bStart = b.startsAt;
    if (aStart != null && bStart != null) {
      final byStart = aStart.compareTo(bStart);
      if (byStart != 0) return byStart;
    }
    final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    return byTitle != 0 ? byTitle : a.occurrenceKey.compareTo(b.occurrenceKey);
  }
}
