/// The one way to put an instant (a point in time) into a request: contract
/// section 12, wire rule 4.
///
/// The server requires an explicit offset on every instant. A local
/// `DateTime` serializes without one (`2026-10-01T18:00:00.000`) and gets a
/// 422, so every `DateTime` that goes into a generated model or query as an
/// instant goes through [ApiInstant.of] first:
///
/// ```dart
/// EventWrite(startsAt: ApiInstant.of(pickedStart), ...)
/// ```
///
/// Calendar dates without a time use `DateOnly` instead.
abstract final class ApiInstant {
  /// [dateTime] in UTC, so it serializes as `2026-10-01T16:00:00.000Z`.
  static DateTime of(DateTime dateTime) => dateTime.toUtc();

  /// [of] for optional values.
  static DateTime? ofNullable(DateTime? dateTime) => dateTime?.toUtc();

  /// The current instant in UTC.
  static DateTime now() => DateTime.now().toUtc();
}
