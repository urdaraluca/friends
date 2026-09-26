import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:friends/features/calendar/domain/rrule_spec.dart';

/// The shared fixtures (contract section 5.9), read from the repository.
final Map<String, Object?> _cases = jsonDecode(
  File('../docs/api/rrule_cases.json').readAsStringSync(),
) as Map<String, Object?>;

List<Map<String, Object?>> _list(String key) =>
    (_cases[key]! as List<Object?>).cast<Map<String, Object?>>();

DateTime _startDate(String value) => DateTime.parse(value.substring(0, 10));

void main() {
  group('docs/api/rrule_cases.json', () {
    for (final valid in _list('valid')) {
      test('valid ${valid['id']} canonicalizes', () {
        final allDay = valid['all_day']! as bool;
        final canonical = canonicalizeRRule(
          valid['input']! as String,
          startDate: _startDate(valid['dtstart_local']! as String),
          allDay: allDay,
        );

        expect(canonical, valid['canonical']);
        // A fixed point.
        expect(
          canonicalizeRRule(
            canonical,
            startDate: _startDate(valid['dtstart_local']! as String),
            allDay: allDay,
          ),
          canonical,
        );
      });
    }

    for (final invalid in _list('invalid')) {
      test('invalid ${invalid['input']} -> ${invalid['reason']}', () {
        final start = _startDate(invalid['start_date']! as String);
        // Timed fixtures start at 19:00 in Bucharest; any instant that day
        // after UTC midnight works for the UNTIL checks.
        final startsAt = DateTime.utc(start.year, start.month, start.day, 16);
        expect(
          () => canonicalizeRRule(
            invalid['input']! as String,
            startDate: start,
            allDay: invalid['all_day']! as bool,
            startsAtUtc: startsAt,
          ),
          throwsA(
            isA<InvalidRRule>().having(
              (e) => e.reason,
              'reason',
              invalid['reason'],
            ),
          ),
        );
      });
    }
  });

  group('canonicalizeRRule', () {
    final thursday = DateTime(2026, 10);

    test('the first failing step wins', () {
      // syntax (step 2) before unsupported_part (step 3) left to right.
      expect(
        () => canonicalizeRRule(
          'FREQ=WEEKLY;;BYSETPOS=1',
          startDate: thursday,
          allDay: false,
        ),
        throwsA(isA<InvalidRRule>().having((e) => e.reason, 'r', 'syntax')),
      );
      // missing_freq (5) before byday_invalid (8).
      expect(
        () => canonicalizeRRule('BYDAY=XX', startDate: thursday, allDay: false),
        throwsA(
          isA<InvalidRRule>().having((e) => e.reason, 'r', 'missing_freq'),
        ),
      );
    });

    test('canonical form', () {
      String c(String raw, {DateTime? start, bool allDay = false}) =>
          canonicalizeRRule(raw, startDate: start ?? thursday, allDay: allDay);

      expect(c('BYDAY=TH;FREQ=WEEKLY'), 'FREQ=WEEKLY;BYDAY=TH');
      expect(c('rrule:freq=weekly;byday=we,mo'), 'FREQ=WEEKLY;BYDAY=MO,WE');
      expect(c('FREQ=WEEKLY'), 'FREQ=WEEKLY;BYDAY=TH');
      expect(
        c('FREQ=MONTHLY', start: DateTime(2026, 10, 15)),
        'FREQ=MONTHLY;BYMONTHDAY=15',
      );
      expect(
        c('FREQ=WEEKLY;INTERVAL=02;COUNT=007'),
        'FREQ=WEEKLY;INTERVAL=2;BYDAY=TH;COUNT=7',
      );
      expect(c('FREQ=MONTHLY;BYDAY=-1FR'), 'FREQ=MONTHLY;BYDAY=-1FR');
      expect(
        c('FREQ=YEARLY;UNTIL=20301231', allDay: true),
        'FREQ=YEARLY;UNTIL=20301231',
      );
    });

    test('UNTIL before the start is rejected; equal is fine', () {
      expect(
        canonicalizeRRule(
          'FREQ=DAILY;UNTIL=20261001',
          startDate: thursday,
          allDay: true,
        ),
        'FREQ=DAILY;UNTIL=20261001',
      );
      expect(
        () => canonicalizeRRule(
          'FREQ=DAILY;UNTIL=20261001T150000Z',
          startDate: thursday,
          allDay: false,
          startsAtUtc: DateTime.utc(2026, 10, 1, 16),
        ),
        throwsA(
          isA<InvalidRRule>().having(
            (e) => e.reason,
            'r',
            'until_before_start',
          ),
        ),
      );
      expect(
        () => canonicalizeRRule(
          'FREQ=DAILY;UNTIL=20260230',
          startDate: thursday,
          allDay: true,
        ),
        throwsA(
          isA<InvalidRRule>().having((e) => e.reason, 'r', 'until_format'),
        ),
      );
    });
  });

  group('RecurrenceSpec', () {
    test('builds canonical rules the server accepts as they are', () {
      final start = DateTime(2026, 10); // 1 October, a Thursday
      final specs = {
        const RecurrenceSpec(
          frequency: RepeatFrequency.weekly,
          weekdays: {4, 1},
        ): 'FREQ=WEEKLY;BYDAY=MO,TH',
        const RecurrenceSpec(
          frequency: RepeatFrequency.monthly,
          monthlyDay: MonthlyByWeekday(-1, 5),
        ): 'FREQ=MONTHLY;BYDAY=-1FR',
        const RecurrenceSpec(
          frequency: RepeatFrequency.monthly,
          monthlyDay: MonthlyLastDay(),
          interval: 2,
        ): 'FREQ=MONTHLY;INTERVAL=2;BYMONTHDAY=-1',
        const RecurrenceSpec(
          frequency: RepeatFrequency.monthly,
          monthlyDay: MonthlyByDate(15),
          end: RepeatCount(6),
        ): 'FREQ=MONTHLY;BYMONTHDAY=15;COUNT=6',
        RecurrenceSpec(
          frequency: RepeatFrequency.yearly,
          end: RepeatUntil(DateTime(2030, 12, 31)),
        ): 'FREQ=YEARLY;UNTIL=20301231',
      };
      for (final MapEntry(key: spec, value: rule) in specs.entries) {
        final built = spec.toRule(allDay: true);
        expect(built, rule);
        expect(
          canonicalizeRRule(built, startDate: start, allDay: true),
          rule,
          reason: 'already canonical',
        );
        expect(RecurrenceSpec.tryParse(rule), spec, reason: rule);
      }
    });

    test('a timed UNTIL is the end of that day in device time, in UTC', () {
      final rule = RecurrenceSpec(
        frequency: RepeatFrequency.weekly,
        weekdays: const {4},
        end: RepeatUntil(DateTime(2026, 12, 31)),
      ).toRule(allDay: false);

      final end = DateTime(2026, 12, 31, 23, 59, 59).toUtc();
      expect(rule, endsWith('Z'));
      expect(rule, contains('UNTIL=${end.year}'));
    });

    test('defaults after the 28th use the last day', () {
      final spec = RecurrenceSpec.startingOn(
        RepeatFrequency.monthly,
        DateTime(2026, 10, 31),
      );
      expect(spec.toRule(allDay: false), 'FREQ=MONTHLY;BYMONTHDAY=-1');
    });

    test('describes itself', () {
      expect(
        const RecurrenceSpec(
          frequency: RepeatFrequency.weekly,
          weekdays: {4},
        ).describe(),
        'Every week on Thursday',
      );
      expect(
        const RecurrenceSpec(
          frequency: RepeatFrequency.monthly,
          interval: 2,
          monthlyDay: MonthlyByWeekday(-1, 5),
          end: RepeatCount(5),
        ).describe(),
        'Every 2 months on the last Friday, 5 times',
      );
      expect(
        const RecurrenceSpec(frequency: RepeatFrequency.yearly).describe(),
        'Every year',
      );
    });
  });
}
