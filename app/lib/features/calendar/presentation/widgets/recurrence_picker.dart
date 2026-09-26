import 'package:flutter/services.dart';
import 'package:friends/features/calendar/domain/rrule_spec.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// The ordinal of [date]'s weekday in its month: 1..4, or -1 when it is the
/// last one (e.g. the last Friday).
int weekdayOrdinal(DateTime date) {
  final next = DateTime(date.year, date.month, date.day + 7);
  if (next.month != date.month) return -1;
  return ((date.day - 1) ~/ 7 + 1).clamp(1, 4);
}

/// Picks how a plan repeats: weekly (which days), monthly (the same day
/// number, the last day, or e.g. "the last Friday"), yearly or daily; every
/// N periods; and until when (never, a date, or N times).
///
/// A monthly plan starting after the 28th can't use its day number (it
/// would skip short months, contract section 5.2); the picker offers the
/// last day or an ordinal weekday instead.
class RecurrencePicker extends StatelessWidget {
  const new({
    required this.spec,
    required this.start,
    required this.onChanged,
    this.error,
    super.key,
  });

  final RecurrenceSpec spec;

  /// The plan's first day (local).
  final DateTime start;
  final ValueChanged<RecurrenceSpec> onChanged;

  /// A human message for an invalid rule, shown under the picker.
  final String? error;

  static const List<(RepeatFrequency, String)> _frequencies = [
    (RepeatFrequency.weekly, 'Weekly'),
    (RepeatFrequency.monthly, 'Monthly'),
    (RepeatFrequency.yearly, 'Yearly'),
    (RepeatFrequency.daily, 'Daily'),
  ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final unit = switch (spec.frequency) {
      RepeatFrequency.daily => 'days',
      RepeatFrequency.weekly => 'weeks',
      RepeatFrequency.monthly => 'months',
      RepeatFrequency.yearly => 'years',
    };
    final ordinal = weekdayOrdinal(start);
    final dayNumberAllowed = start.day <= 28;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<RepeatFrequency>(
          segments: [
            for (final (frequency, label) in _frequencies)
              ButtonSegment(value: frequency, label: Text(label)),
          ],
          selected: {spec.frequency},
          onSelectionChanged: (selection) {
            final frequency = selection.single;
            final defaults = RecurrenceSpec.startingOn(frequency, start);
            onChanged(
              defaults.copyWith(interval: spec.interval, end: spec.end),
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Every'),
            const SizedBox(width: 8),
            SizedBox(
              width: 56,
              child: TextFormField(
                key: ValueKey('interval-${spec.frequency}'),
                initialValue: '${spec.interval}',
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                decoration: const InputDecoration(isDense: true),
                onChanged: (value) {
                  final interval = int.tryParse(value);
                  if (interval != null && interval >= 1) {
                    onChanged(spec.copyWith(interval: interval));
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Text(
              spec.interval == 1 ? unit.substring(0, unit.length - 1) : unit,
            ),
          ],
        ),
        if (spec.frequency == RepeatFrequency.weekly) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            children: [
              for (var day = 1; day <= 7; day++)
                FilterChip(
                  label: Text(weekdayNames[day - 1].substring(0, 3)),
                  selected: spec.weekdays.contains(day),
                  onSelected: (on) {
                    final days = {...spec.weekdays};
                    if (on) {
                      days.add(day);
                    } else if (days.length > 1) {
                      days.remove(day);
                    }
                    onChanged(spec.copyWith(weekdays: days));
                  },
                ),
            ],
          ),
        ],
        if (spec.frequency == RepeatFrequency.monthly) ...[
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: switch (spec.monthlyDay) {
              MonthlyByDate() => 'date',
              MonthlyLastDay() => 'last',
              MonthlyByWeekday() => 'weekday',
              null => null,
            },
            onChanged: (value) => onChanged(
              spec.copyWith(
                monthlyDay: switch (value) {
                  'date' => MonthlyByDate(start.day),
                  'last' => const MonthlyLastDay(),
                  _ => MonthlyByWeekday(ordinal, start.weekday),
                },
              ),
            ),
            child: Column(
              children: [
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'date',
                  enabled: dayNumberAllowed,
                  title: Text('On day ${start.day}'),
                  subtitle: dayNumberAllowed
                      ? null
                      : const Text('Not every month has this day'),
                ),
                const RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'last',
                  title: Text('On the last day'),
                ),
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'weekday',
                  title: Text(
                    'On the ${ordinalNames[ordinal]} '
                    '${weekdayNames[start.weekday - 1]}',
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text('Ends', style: textTheme.labelLarge),
        RadioGroup<String>(
          groupValue: switch (spec.end) {
            RepeatForever() => 'never',
            RepeatUntil() => 'until',
            RepeatCount() => 'count',
          },
          onChanged: (value) => onChanged(
            spec.copyWith(
              end: switch (value) {
                'until' => RepeatUntil(
                  DateTime(start.year, start.month + 3, start.day),
                ),
                'count' => const RepeatCount(10),
                _ => const RepeatForever(),
              },
            ),
          ),
          child: Column(
            children: [
              const RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: 'never',
                title: Text('Never'),
              ),
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: 'until',
                title: Row(
                  children: [
                    const Text('On '),
                    TextButton(
                      onPressed: spec.end is RepeatUntil
                          ? () async {
                              final current = (spec.end as RepeatUntil).date;
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: current,
                                firstDate: start,
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) {
                                onChanged(
                                  spec.copyWith(end: RepeatUntil(picked)),
                                );
                              }
                            }
                          : null,
                      child: Text(switch (spec.end) {
                        RepeatUntil(:final date) => DateFormat.yMMMd().format(
                          date,
                        ),
                        _ => 'a date',
                      }),
                    ),
                  ],
                ),
              ),
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: 'count',
                title: Row(
                  children: [
                    const Text('After '),
                    SizedBox(
                      width: 56,
                      child: TextFormField(
                        key: ValueKey('count-${spec.end is RepeatCount}'),
                        enabled: spec.end is RepeatCount,
                        initialValue: switch (spec.end) {
                          RepeatCount(:final count) => '$count',
                          _ => '10',
                        },
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        decoration: const InputDecoration(isDense: true),
                        onChanged: (value) {
                          final count = int.tryParse(value);
                          if (count != null && count >= 1) {
                            onChanged(spec.copyWith(end: RepeatCount(count)));
                          }
                        },
                      ),
                    ),
                    const Text(' times'),
                  ],
                ),
              ),
            ],
          ),
        ),
        Text(spec.describe(), style: textTheme.bodySmall),
        if (error case final error?)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
