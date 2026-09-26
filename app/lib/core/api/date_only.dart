/// Helpers for calendar dates without a time (due dates, birthdays, all-day
/// events): contract sections 1.3 and 12, wire rule 3.
///
/// A date is a **UTC midnight** `DateTime.utc(y, m, d)`. The generated client
/// sends it with `toIso8601String()` (`2026-10-01T00:00:00.000Z`), which the
/// server's `ApiDate` accepts (a midnight, with or without `Z`) and never
/// shifts between zones.
///
/// Why UTC and not a local `DateTime(y, m, d)`: local midnight doesn't exist
/// on every day. Where DST starts at midnight (Santiago, Cairo, Beirut,
/// Havana, the Azores), `DateTime(2026, 9, 6)` in Santiago is 01:00, which
/// goes out as `2026-09-06T01:00:00.000` and gets a 422. UTC has no gaps.
///
/// Only the year, month and day of a date mean anything:
/// - never call `.toUtc()` or `.toLocal()` on one (in Bucharest,
///   `DateTime(2026, 10, 1).toUtc()` is 30 September, 21:00);
/// - compare dates with [isSameDay] and [compare], not `==` or `isBefore`:
///   a UTC and a local midnight of the same date are different instants.
///
/// Dates in responses (`"2026-10-01"`) parse, in the generated `fromJson`, to
/// a **local** `DateTime` (`DateTime.parse` of a string without an offset).
/// Their year, month and day are right, but on a DST-gap day the time is
/// 01:00, so pass a server date through [from] before sending it back:
///
/// ```dart
/// ActivityUpdate(dueDate: DateOnly.fromNullable(activity.dueDate), ...)
/// ```
abstract final class DateOnly {
  /// The date [year]-[month]-[day] as a UTC midnight.
  static DateTime of(int year, int month, int day) =>
      DateTime.utc(year, month, day);

  /// The calendar date of [dateTime] as seen in its own zone (local or UTC),
  /// as a UTC midnight.
  static DateTime from(DateTime dateTime) =>
      DateTime.utc(dateTime.year, dateTime.month, dateTime.day);

  /// [from] for optional values.
  static DateTime? fromNullable(DateTime? dateTime) =>
      dateTime == null ? null : from(dateTime);

  /// Today on this device.
  static DateTime today() => from(DateTime.now());

  /// `YYYY-MM-DD`, for query strings, keys and display.
  static String format(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static final _pattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  /// Parses `YYYY-MM-DD` to a UTC midnight.
  ///
  /// Throws a [FormatException] for any other shape or an impossible date
  /// such as `2026-02-30`.
  static DateTime parse(String value) {
    final result = tryParse(value);
    if (result == null) {
      throw FormatException('Not a YYYY-MM-DD date', value);
    }
    return result;
  }

  /// Like [parse], but returns null instead of throwing.
  static DateTime? tryParse(String value) {
    final match = _pattern.firstMatch(value);
    if (match == null) return null;
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    final date = DateTime.utc(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  /// Whether [a] and [b] fall on the same calendar date.
  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Orders [a] and [b] by calendar date only (a `Comparator`).
  static int compare(DateTime a, DateTime b) {
    if (a.year != b.year) return a.year.compareTo(b.year);
    if (a.month != b.month) return a.month.compareTo(b.month);
    return a.day.compareTo(b.day);
  }
}
