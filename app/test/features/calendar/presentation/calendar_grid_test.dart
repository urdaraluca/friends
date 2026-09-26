import 'package:flutter_test/flutter_test.dart';
import 'package:friends/features/calendar/data/calendar_providers.dart';
import 'package:friends/features/calendar/presentation/widgets/calendar_view.dart';
import 'package:friends/features/calendar/presentation/widgets/recurrence_picker.dart';

void main() {
  test('the grid starts on the Monday on or before the first shown day', () {
    expect(
      gridStart(DateTime(2026, 10, 15), CalendarSpan.month),
      DateTime(2026, 9, 28),
    );
    expect(
      gridStart(DateTime(2026, 10, 15), CalendarSpan.week),
      DateTime(2026, 10, 12),
    );
    // A month starting on a Monday starts there.
    expect(
      gridStart(DateTime(2027, 3, 10), CalendarSpan.month),
      DateTime(2027, 3),
    );
    // Midnights stay midnights, whatever the DST changes in between.
    for (var month = 1; month <= 12; month++) {
      final start = gridStart(DateTime(2026, month, 20), CalendarSpan.month);
      expect((start.hour, start.minute), (0, 0), reason: 'month $month');
      expect(start.weekday, DateTime.monday);
    }
  });

  test('weekdayOrdinal counts calendar days, not 24-hour steps', () {
    // 25 October 2026, the day clocks go back in Europe: the last Sunday.
    expect(weekdayOrdinal(DateTime(2026, 10, 25)), -1);
    expect(weekdayOrdinal(DateTime(2026, 10, 18)), 3);
    expect(weekdayOrdinal(DateTime(2026, 10)), 1);
    // 29 March 2027 (after the spring change) is the last Monday.
    expect(weekdayOrdinal(DateTime(2027, 3, 29)), -1);
  });
}
