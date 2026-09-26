import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/date_only.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/features/calendar/domain/occurrence_index.dart';

import '../../../helpers/api_fixtures.dart';

Occurrence timed(String title, DateTime startUtc, DateTime endUtc) =>
    Occurrence.fromJson(
      occurrenceJson(
        title: title,
        startsAt: startUtc.toIso8601String(),
        endsAt: endUtc.toIso8601String(),
      ),
    );

Occurrence allDay(String title, String start, [String? end]) =>
    Occurrence.fromJson(
      occurrenceJson(title: title, startDate: start, endDate: end ?? start),
    );

List<String> titlesOn(OccurrenceIndex index, DateTime day) =>
    index.on(day).map((o) => o.title).toList();

void main() {
  test('multi-day all-day events are on every day, end inclusive', () {
    final index = OccurrenceIndex([allDay('Trip', '2026-10-09', '2026-10-11')]);

    expect(titlesOn(index, DateOnly.of(2026, 10, 8)), isEmpty);
    expect(titlesOn(index, DateOnly.of(2026, 10, 9)), ['Trip']);
    expect(titlesOn(index, DateOnly.of(2026, 10, 10)), ['Trip']);
    expect(titlesOn(index, DateOnly.of(2026, 10, 11)), ['Trip']);
    expect(titlesOn(index, DateOnly.of(2026, 10, 12)), isEmpty);
  });

  test('a timed event crossing midnight shows on both local days', () {
    // 22:00 to 02:00 in the device's zone.
    final start = DateTime(2026, 10, 3, 22);
    final index = OccurrenceIndex([
      timed(
        'Party',
        start.toUtc(),
        start.add(const Duration(hours: 4)).toUtc(),
      ),
    ]);

    expect(titlesOn(index, DateTime(2026, 10, 3)), ['Party']);
    expect(titlesOn(index, DateTime(2026, 10, 4)), ['Party']);
    expect(titlesOn(index, DateTime(2026, 10, 5)), isEmpty);
  });

  test('ending exactly at midnight does not spill into the next day', () {
    final start = DateTime(2026, 10, 3, 20);
    final index = OccurrenceIndex([
      timed('Dinner', start.toUtc(), DateTime(2026, 10, 4).toUtc()),
    ]);

    expect(titlesOn(index, DateTime(2026, 10, 3)), ['Dinner']);
    expect(titlesOn(index, DateTime(2026, 10, 4)), isEmpty);
  });

  test('a DST weekend keeps each event on its local day', () {
    // The last Sunday of October: clocks go back in much of Europe. Daily
    // 19:00 events around it stay on their own days whatever the offset.
    final index = OccurrenceIndex([
      for (var day = 24; day <= 26; day++)
        timed(
          'Walk $day',
          DateTime(2026, 10, day, 19).toUtc(),
          DateTime(2026, 10, day, 20).toUtc(),
        ),
    ]);

    for (var day = 24; day <= 26; day++) {
      expect(titlesOn(index, DateTime(2026, 10, day)), ['Walk $day']);
    }
  });

  test('all-day first, then timed by start, then by title', () {
    final index = OccurrenceIndex([
      timed(
        'Late',
        DateTime(2026, 10, 3, 20).toUtc(),
        DateTime(2026, 10, 3, 21).toUtc(),
      ),
      allDay('B-day', '2026-10-03'),
      timed(
        'Early',
        DateTime(2026, 10, 3, 9).toUtc(),
        DateTime(2026, 10, 3, 10).toUtc(),
      ),
      allDay('Anniversary', '2026-10-03'),
    ]);

    expect(titlesOn(index, DateTime(2026, 10, 3)), [
      'Anniversary',
      'B-day',
      'Early',
      'Late',
    ]);
  });
}
