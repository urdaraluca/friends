import 'package:material_ui/material_ui.dart' show immutable;

/// The restricted RRULE subset of the API (contract section 5), mirrored on
/// the client: [canonicalizeRRule] follows the server's 15 validation steps
/// in order (section 5.2), so the form can explain a bad rule before
/// sending it; [RecurrenceSpec] builds and reads the rules the recurrence
/// picker offers. The client never expands rules: the server returns
/// occurrences.
///
/// Both are table-tested against `docs/api/rrule_cases.json`.

/// A rule outside the allowed subset. [reason] is the section 5.2 reason
/// (the API's `errors[0].type` for `422 invalid_rrule`).
class InvalidRRule implements Exception {
  const new(this.reason, this.message);

  final String reason;
  final String message;

  @override
  String toString() => 'InvalidRRule($reason: $message)';
}

/// Weekday codes, Monday first (the RFC's default week start).
const rruleWeekdays = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

const _frequencies = ['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'];
const _partNames = [
  'FREQ',
  'INTERVAL',
  'BYDAY',
  'BYMONTHDAY',
  'COUNT',
  'UNTIL',
];
const maxInterval = 99;
const maxCount = 730;

final _interval = RegExp(r'^[0-9]{1,3}$');
final _count = RegExp(r'^[0-9]{1,4}$');
final _monthlyByday = RegExp(r'^(-1|[1-4])(MO|TU|WE|TH|FR|SA|SU)$');
final _bymonthday = RegExp(r'^-?[0-9]{1,2}$');
final _untilTimed = RegExp(
  r'^([0-9]{4})([0-9]{2})([0-9]{2})T([0-9]{2})([0-9]{2})([0-9]{2})Z$',
);
final _untilDate = RegExp(r'^([0-9]{4})([0-9]{2})([0-9]{2})$');
final _lineBreak = RegExp('[\n\r\v\f\x1c\x1d\x1e\x85  ]');

/// The canonical form of [raw], or an [InvalidRRule] with the first failing
/// step's reason (contract section 5.2).
///
/// [startDate] is the event's local start date (its year, month and day
/// count); [startsAtUtc] is a timed event's start instant, used to check
/// `UNTIL` (when null, that last check is left to the server).
String canonicalizeRRule(
  String raw, {
  required DateTime startDate,
  required bool allDay,
  DateTime? startsAtUtc,
}) {
  // 1. Trim; no line breaks or DTSTART; strip "RRULE:"; uppercase.
  var text = raw.trim();
  if (_lineBreak.hasMatch(text) || text.toUpperCase().contains('DTSTART')) {
    throw const InvalidRRule(
      'embedded_dtstart',
      'Send the rule only: no DTSTART and no line breaks.',
    );
  }
  if (text.length >= 6 && text.substring(0, 6).toUpperCase() == 'RRULE:') {
    text = text.substring(6);
  }
  text = text.toUpperCase();

  // 2-4. NAME=VALUE parts, left to right: syntax, known name, no repeats.
  final parts = <String, String>{};
  for (final part in text.split(';')) {
    final equals = part.indexOf('=');
    final name = equals < 0 ? part : part.substring(0, equals);
    final value = equals < 0 ? '' : part.substring(equals + 1);
    if (equals < 0 || name.isEmpty || value.isEmpty) {
      throw const InvalidRRule(
        'syntax',
        "Each part must be NAME=VALUE, separated by ';'.",
      );
    }
    if (!_partNames.contains(name)) {
      throw InvalidRRule('unsupported_part', '$name is not supported.');
    }
    if (parts.containsKey(name)) {
      throw InvalidRRule('duplicate_part', '$name appears more than once.');
    }
    parts[name] = value;
  }

  // 5-6. FREQ.
  final freq = parts['FREQ'];
  if (freq == null) {
    throw const InvalidRRule('missing_freq', 'FREQ is required.');
  }
  if (!_frequencies.contains(freq)) {
    throw const InvalidRRule(
      'unsupported_freq',
      'FREQ must be DAILY, WEEKLY, MONTHLY or YEARLY.',
    );
  }

  // 7. INTERVAL.
  var interval = 1;
  if (parts['INTERVAL'] case final raw?) {
    final value = _interval.hasMatch(raw) ? int.parse(raw) : 0;
    if (value < 1 || value > maxInterval) {
      throw const InvalidRRule(
        'interval_out_of_range',
        'INTERVAL must be between 1 and $maxInterval.',
      );
    }
    interval = value;
  }

  // 8. BYDAY.
  var byday = parts['BYDAY'];
  if (byday != null) byday = _canonicalByday(freq, byday);

  // 9. BYMONTHDAY.
  int? bymonthday;
  if (parts['BYMONTHDAY'] case final raw?) {
    if (freq != 'MONTHLY' || byday != null || !_bymonthday.hasMatch(raw)) {
      throw _bymonthdayInvalid();
    }
    final value = int.parse(raw);
    if (!((value >= 1 && value <= 28) || value == -1)) {
      throw _bymonthdayInvalid();
    }
    bymonthday = value;
  }

  // 10. Defaults from the start.
  if (freq == 'WEEKLY' && byday == null) {
    byday = rruleWeekdays[startDate.weekday - 1];
  }
  if (freq == 'MONTHLY' && byday == null && bymonthday == null) {
    if (startDate.day > 28) {
      throw const InvalidRRule(
        'monthly_day_over_28',
        'A monthly rule starting after the 28th would skip short months; '
            'use the last day of the month instead.',
      );
    }
    bymonthday = startDate.day;
  }

  // 11. No yearly rule from 29 February.
  if (freq == 'YEARLY' && startDate.month == 2 && startDate.day == 29) {
    throw const InvalidRRule(
      'yearly_feb29',
      "A yearly rule can't start on 29 February.",
    );
  }

  // 12-13. COUNT.
  var count = parts['COUNT'];
  final until = parts['UNTIL'];
  if (count != null && until != null) {
    throw const InvalidRRule(
      'count_and_until',
      'Use COUNT or UNTIL, not both.',
    );
  }
  if (count != null) {
    final value = _count.hasMatch(count) ? int.parse(count) : 0;
    if (value < 1 || value > maxCount) {
      throw const InvalidRRule(
        'count_out_of_range',
        'COUNT must be between 1 and $maxCount.',
      );
    }
    count = '$value';
  }

  // 14-15. UNTIL: the format for the event type, then not before the start.
  if (until != null) {
    if (allDay) {
      final day = _parseUntilDate(until);
      if (day.isBefore(
        DateTime.utc(startDate.year, startDate.month, startDate.day),
      )) {
        throw _untilBeforeStart();
      }
    } else {
      final instant = _parseUntilInstant(until);
      if (startsAtUtc != null && instant.isBefore(startsAtUtc.toUtc())) {
        throw _untilBeforeStart();
      }
    }
  }

  return [
    'FREQ=$freq',
    if (interval != 1) 'INTERVAL=$interval',
    if (byday != null) 'BYDAY=$byday',
    if (bymonthday != null) 'BYMONTHDAY=$bymonthday',
    if (count != null) 'COUNT=$count' else if (until != null) 'UNTIL=$until',
  ].join(';');
}

String _canonicalByday(String freq, String value) {
  if (freq == 'WEEKLY') {
    final days = value.split(',');
    if (!days.every(rruleWeekdays.contains) ||
        days.toSet().length != days.length) {
      throw const InvalidRRule(
        'byday_invalid',
        'Weekly BYDAY is a list of distinct days (MO..SU).',
      );
    }
    days.sort(
      (a, b) => rruleWeekdays.indexOf(a).compareTo(rruleWeekdays.indexOf(b)),
    );
    return days.join(',');
  }
  if (freq == 'MONTHLY') {
    if (!_monthlyByday.hasMatch(value)) {
      throw const InvalidRRule(
        'byday_invalid',
        'Monthly BYDAY is one ordinal weekday: 1 to 4 or -1, e.g. 2TU or '
            '-1FR.',
      );
    }
    return value;
  }
  throw const InvalidRRule(
    'byday_invalid',
    'BYDAY is only allowed with WEEKLY or MONTHLY.',
  );
}

InvalidRRule _bymonthdayInvalid() => const InvalidRRule(
  'bymonthday_invalid',
  'BYMONTHDAY is monthly only: one day from 1 to 28 or -1 (the last day), '
      'without BYDAY.',
);

InvalidRRule _untilBeforeStart() =>
    const InvalidRRule('until_before_start', 'UNTIL is before the start.');

DateTime _parseUntilDate(String value) {
  final match = _untilDate.firstMatch(value);
  final date = match == null ? null : _date(match);
  if (date == null) {
    throw const InvalidRRule('until_format', 'UNTIL must be a date YYYYMMDD.');
  }
  return date;
}

DateTime _parseUntilInstant(String value) {
  final match = _untilTimed.firstMatch(value);
  const error = InvalidRRule(
    'until_format',
    'UNTIL must be a UTC date-time YYYYMMDDTHHMMSSZ.',
  );
  if (match == null) throw error;
  final date = _date(match);
  final (hour, minute, second) = (
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
  );
  if (date == null || hour > 23 || minute > 59 || second > 59) throw error;
  return DateTime.utc(date.year, date.month, date.day, hour, minute, second);
}

/// The real date of groups 1-3 of [match], or null for e.g. 20260230.
DateTime? _date(RegExpMatch match) {
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime.utc(year, month, day);
  return date.year == year && date.month == month && date.day == day
      ? date
      : null;
}

/// Human messages for the `invalid_rrule` reasons (contract section 5.2).
String rruleReasonMessage(String reason) => switch (reason) {
  'monthly_day_over_28' =>
    'This month-day doesn\'t exist in every month. Pick "last day" or a '
        'weekday such as "last Friday".',
  'yearly_feb29' =>
    "A yearly plan can't start on 29 February. Start on 28 February or "
        '1 March.',
  'until_before_start' => 'The end date is before the start.',
  'count_out_of_range' => 'Repeat between 1 and $maxCount times.',
  'interval_out_of_range' => 'Repeat every 1 to $maxInterval periods.',
  'count_and_until' => 'End on a date or after a number of times, not both.',
  'byday_invalid' => 'Pick the days again.',
  _ => "This repeat pattern isn't supported.",
};

// --- the picker model ---

/// How often a plan repeats, as the recurrence picker offers it.
enum RepeatFrequency { weekly, monthly, yearly, daily }

/// Which day of the month a monthly plan uses.
sealed class MonthlyDay {
  const new();
}

/// The same day number every month (1..28).
final class MonthlyByDate extends MonthlyDay {
  const new(this.day);

  final int day;
}

/// The last day of every month (`BYMONTHDAY=-1`).
final class MonthlyLastDay extends MonthlyDay {
  const new();
}

/// E.g. "the second Tuesday" (ordinal 2) or "the last Friday" (-1).
final class MonthlyByWeekday extends MonthlyDay {
  const new(this.ordinal, this.weekday);

  /// 1..4, or -1 for the last.
  final int ordinal;

  /// 1 = Monday … 7 = Sunday (`DateTime.weekday`).
  final int weekday;
}

/// When a repeating plan stops.
sealed class RepeatEnd {
  const new();
}

final class RepeatForever extends RepeatEnd {
  const new();
}

/// Through [date] (inclusive).
final class RepeatUntil extends RepeatEnd {
  const new(this.date);

  /// A calendar date (year, month and day count).
  final DateTime date;
}

/// After [count] occurrences.
final class RepeatCount extends RepeatEnd {
  const new(this.count);

  final int count;
}

/// A repeating plan as the picker shows it, convertible to and from the
/// canonical rule.
@immutable
class RecurrenceSpec {
  const new({
    required this.frequency,
    this.interval = 1,
    this.weekdays = const {},
    this.monthlyDay,
    this.end = const RepeatForever(),
  });

  /// Defaults for a plan starting on [start]: weekly on its weekday, monthly
  /// on its day (or the last day after the 28th).
  factory startingOn(RepeatFrequency frequency, DateTime start) =>
      RecurrenceSpec(
        frequency: frequency,
        weekdays: {start.weekday},
        monthlyDay: start.day > 28
            ? const MonthlyLastDay()
            : MonthlyByDate(start.day),
      );

  final RepeatFrequency frequency;
  final int interval;

  /// Weekly: 1 = Monday … 7 = Sunday.
  final Set<int> weekdays;

  /// Monthly: which day.
  final MonthlyDay? monthlyDay;
  final RepeatEnd end;

  RecurrenceSpec copyWith({
    RepeatFrequency? frequency,
    int? interval,
    Set<int>? weekdays,
    MonthlyDay? monthlyDay,
    RepeatEnd? end,
  }) => RecurrenceSpec(
    frequency: frequency ?? this.frequency,
    interval: interval ?? this.interval,
    weekdays: weekdays ?? this.weekdays,
    monthlyDay: monthlyDay ?? this.monthlyDay,
    end: end ?? this.end,
  );

  /// The rule for this spec. [allDay] picks the `UNTIL` format: a date, or
  /// the end of that day in device-local time as a UTC instant.
  String toRule({required bool allDay}) {
    final parts = <String>[
      'FREQ=${switch (frequency) {
        RepeatFrequency.daily => 'DAILY',
        RepeatFrequency.weekly => 'WEEKLY',
        RepeatFrequency.monthly => 'MONTHLY',
        RepeatFrequency.yearly => 'YEARLY',
      }}',
      if (interval != 1) 'INTERVAL=$interval',
    ];
    if (frequency == RepeatFrequency.weekly && weekdays.isNotEmpty) {
      final days = weekdays.toList()..sort();
      parts.add('BYDAY=${days.map((d) => rruleWeekdays[d - 1]).join(',')}');
    }
    if (frequency == RepeatFrequency.monthly) {
      switch (monthlyDay) {
        case MonthlyByDate(:final day):
          parts.add('BYMONTHDAY=$day');
        case MonthlyLastDay():
          parts.add('BYMONTHDAY=-1');
        case MonthlyByWeekday(:final ordinal, :final weekday):
          parts.add('BYDAY=$ordinal${rruleWeekdays[weekday - 1]}');
        case null:
          break;
      }
    }
    switch (end) {
      case RepeatForever():
        break;
      case RepeatCount(:final count):
        parts.add('COUNT=$count');
      case RepeatUntil(:final date):
        if (allDay) {
          parts.add(
            'UNTIL=${_digits(date.year, 4)}${_digits(date.month)}'
            '${_digits(date.day)}',
          );
        } else {
          final end = DateTime(
            date.year,
            date.month,
            date.day,
            23,
            59,
            59,
          ).toUtc();
          parts.add(
            'UNTIL=${_digits(end.year, 4)}${_digits(end.month)}'
            '${_digits(end.day)}T${_digits(end.hour)}${_digits(end.minute)}'
            '${_digits(end.second)}Z',
          );
        }
    }
    return parts.join(';');
  }

  /// Reads a canonical rule back into the picker, or null for a rule the
  /// picker can't show (it then keeps the rule as it is).
  static RecurrenceSpec? tryParse(String rule) {
    final parts = <String, String>{
      for (final part in rule.toUpperCase().split(';'))
        if (part.contains('='))
          part.substring(0, part.indexOf('=')): part.substring(
            part.indexOf('=') + 1,
          ),
    };
    final frequency = switch (parts['FREQ']) {
      'DAILY' => RepeatFrequency.daily,
      'WEEKLY' => RepeatFrequency.weekly,
      'MONTHLY' => RepeatFrequency.monthly,
      'YEARLY' => RepeatFrequency.yearly,
      _ => null,
    };
    if (frequency == null) return null;
    final interval = int.tryParse(parts['INTERVAL'] ?? '1') ?? 1;
    var weekdays = <int>{};
    MonthlyDay? monthlyDay;
    final byday = parts['BYDAY'];
    if (frequency == RepeatFrequency.weekly && byday != null) {
      weekdays = {
        for (final day in byday.split(',')) rruleWeekdays.indexOf(day) + 1,
      };
      if (weekdays.contains(0)) return null;
    }
    if (frequency == RepeatFrequency.monthly) {
      if (byday != null) {
        final match = _monthlyByday.firstMatch(byday);
        if (match == null) return null;
        monthlyDay = MonthlyByWeekday(
          int.parse(match.group(1)!),
          rruleWeekdays.indexOf(match.group(2)!) + 1,
        );
      } else if (parts['BYMONTHDAY'] case final day?) {
        final value = int.tryParse(day);
        if (value == null) return null;
        monthlyDay = value == -1
            ? const MonthlyLastDay()
            : MonthlyByDate(value);
      }
    }
    RepeatEnd end = const RepeatForever();
    if (parts['COUNT'] case final count?) {
      end = RepeatCount(int.tryParse(count) ?? 1);
    } else if (parts['UNTIL'] case final until?) {
      final match =
          _untilTimed.firstMatch(until) ?? _untilDate.firstMatch(until);
      final date = match == null ? null : _date(match);
      if (date == null) return null;
      final instant = _untilTimed.hasMatch(until)
          ? _parseUntilInstant(until).toLocal()
          : date;
      end = RepeatUntil(DateTime(instant.year, instant.month, instant.day));
    }
    return RecurrenceSpec(
      frequency: frequency,
      interval: interval,
      weekdays: weekdays,
      monthlyDay: monthlyDay,
      end: end,
    );
  }

  /// "Every week on Thursday", "Every 2 months on the last Friday", "Every
  /// year, 5 times".
  String describe() {
    final sortedDays = weekdays.toList()..sort();
    final unit = switch (frequency) {
      RepeatFrequency.daily => ('day', 'days'),
      RepeatFrequency.weekly => ('week', 'weeks'),
      RepeatFrequency.monthly => ('month', 'months'),
      RepeatFrequency.yearly => ('year', 'years'),
    };
    final every = interval == 1
        ? 'Every ${unit.$1}'
        : 'Every $interval ${unit.$2}';
    final on = switch (frequency) {
      RepeatFrequency.weekly when weekdays.isNotEmpty =>
        ' on ${_list([for (final d in sortedDays) weekdayNames[d - 1]])}',
      RepeatFrequency.monthly => switch (monthlyDay) {
        MonthlyByDate(:final day) => ' on day $day',
        MonthlyLastDay() => ' on the last day',
        MonthlyByWeekday(:final ordinal, :final weekday) =>
          ' on the ${ordinalNames[ordinal]} ${weekdayNames[weekday - 1]}',
        null => '',
      },
      _ => '',
    };
    final until = switch (end) {
      RepeatForever() => '',
      RepeatCount(:final count) => ', $count ${count == 1 ? 'time' : 'times'}',
      RepeatUntil(:final date) =>
        ', until ${date.day} ${monthNames[date.month - 1]} ${date.year}',
    };
    return '$every$on$until';
  }

  @override
  bool operator ==(Object other) =>
      other is RecurrenceSpec &&
      other.toRule(allDay: true) == toRule(allDay: true);

  @override
  int get hashCode => toRule(allDay: true).hashCode;

  static String _digits(int value, [int width = 2]) =>
      value.toString().padLeft(width, '0');

  static String _list(List<String> items) => items.length <= 1
      ? items.join()
      : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
}

const weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const ordinalNames = {
  1: 'first',
  2: 'second',
  3: 'third',
  4: 'fourth',
  -1: 'last',
};

const monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
