import 'package:friends/core/api/date_only.dart';
import 'package:friends/core/api/generated/export.dart';

/// My answers being edited: a status per date and slot, or none (unknown).
class AvailabilityDraft {
  new(Iterable<AvailabilityEntry> saved)
    : _saved = {
        for (final entry in saved) _key(entry.date, entry.slot): entry.status,
      } {
    _answers.addAll(_saved);
  }

  final Map<String, AvailabilityStatus> _saved;
  final Map<String, AvailabilityStatus> _answers = {};

  static String _key(DateTime day, AvailabilitySlot slot) =>
      '${DateOnly.format(day)}|${slot.json}';

  /// The slot's own answer, or null.
  AvailabilityStatus? status(DateTime day, AvailabilitySlot slot) =>
      _answers[_key(day, slot)];

  /// What counts for [slot]: its own answer, else (for a part of the day)
  /// the day's all-day answer (contract section 13).
  AvailabilityStatus? effective(DateTime day, AvailabilitySlot slot) =>
      status(day, slot) ??
      (slot == AvailabilitySlot.allDay
          ? null
          : status(day, AvailabilitySlot.allDay));

  void set(DateTime day, AvailabilitySlot slot, AvailabilityStatus? value) {
    final key = _key(day, slot);
    if (value == null) {
      _answers.remove(key);
    } else {
      _answers[key] = value;
    }
  }

  /// Unknown → free → maybe → busy → unknown.
  static AvailabilityStatus? next(AvailabilityStatus? status) =>
      switch (status) {
        null => AvailabilityStatus.free,
        AvailabilityStatus.free => AvailabilityStatus.maybe,
        AvailabilityStatus.maybe => AvailabilityStatus.busy,
        AvailabilityStatus.busy || AvailabilityStatus.$unknown => null,
      };

  /// Copies the 7 days from [fromMonday] onto the 7 days from [toMonday],
  /// every slot, replacing what was there.
  void copyWeek(DateTime fromMonday, DateTime toMonday) {
    for (var offset = 0; offset < 7; offset++) {
      final from = DateTime(
        fromMonday.year,
        fromMonday.month,
        fromMonday.day + offset,
      );
      final to = DateTime(toMonday.year, toMonday.month, toMonday.day + offset);
      for (final slot in AvailabilitySlot.$valuesDefined) {
        set(to, slot, status(from, slot));
      }
    }
  }

  /// Whether anything differs from what was saved.
  bool get dirty =>
      _answers.length != _saved.length ||
      _answers.entries.any((e) => _saved[e.key] != e.value);

  /// The answers with `from <= date < to`, to send (dates as UTC midnights).
  List<AvailabilityEntryWrite> entries(DateTime from, DateTime to) {
    final start = DateOnly.format(from);
    final end = DateOnly.format(to);
    final keys = _answers.keys.toList()..sort();
    return [
      for (final key in keys)
        if (key.split('|').first.compareTo(start) >= 0 &&
            key.split('|').first.compareTo(end) < 0)
          AvailabilityEntryWrite(
            date: DateOnly.parse(key.split('|').first),
            slot: AvailabilitySlot.fromJson(key.split('|').last),
            status: _answers[key]!,
          ),
    ];
  }
}
