// The legacy boundary: table_calendar is built on package:flutter/material.dart
// (see CalendarView). Nothing else in the app imports it.
import 'package:flutter/material.dart' as legacy show Material, MaterialType;
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/theme/app_theme.dart';
import 'package:friends/features/calendar/data/calendar_providers.dart';
import 'package:friends/features/calendar/domain/occurrence_index.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_calendar/table_calendar.dart';

/// The fixed colour of birthdays without a category (member birthdays).
const birthdayColor = Color(0xFFE91E63);

/// An occurrence's marker colour: its category's, else the birthday colour
/// for birthdays, else the theme's primary colour.
Color occurrenceColor(Occurrence occurrence, ColorScheme colors) =>
    HexColor.tryParse(occurrence.color) ??
    (occurrence.kind == EventKind.birthday ? birthdayColor : colors.primary);

/// The first day of the grid for [focused] and [span]: the Monday on or
/// before the first shown day.
DateTime gridStart(DateTime focused, CalendarSpan span) {
  final first = span == CalendarSpan.month
      ? DateTime(focused.year, focused.month)
      : DateTime(focused.year, focused.month, focused.day);
  return DateTime(first.year, first.month, first.day - (first.weekday - 1));
}

/// How many days the grid of [span] covers (a month shows up to 6 weeks).
int gridDays(CalendarSpan span) => switch (span) {
  CalendarSpan.month => 42,
  CalendarSpan.twoWeeks => 14,
  CalendarSpan.week => 7,
};

/// The month / two-week / week grid with a marker per occurrence: a cake
/// for birthdays, a ring for recurring events, a dot for one-time ones, in
/// the occurrence's colour.
///
/// Wraps `table_calendar`, so it can be swapped out.
class CalendarView extends StatelessWidget {
  const new({
    required this.focusedDay,
    required this.selectedDay,
    required this.span,
    required this.index,
    required this.onDaySelected,
    required this.onPageChanged,
    required this.onSpanChanged,
    super.key,
  });

  final DateTime focusedDay;
  final DateTime selectedDay;
  final CalendarSpan span;
  final OccurrenceIndex index;
  final void Function(DateTime selected) onDaySelected;
  final void Function(DateTime focused) onPageChanged;
  final void Function(CalendarSpan span) onSpanChanged;

  static const Map<CalendarSpan, CalendarFormat> _formats = {
    CalendarSpan.month: CalendarFormat.month,
    CalendarSpan.twoWeeks: CalendarFormat.twoWeeks,
    CalendarSpan.week: CalendarFormat.week,
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // table_calendar still imports package:flutter/material.dart. The bridge
    // gives it a legacy theme and localizations, and a transparent legacy
    // Material hosts its ink buttons. Both go once table_calendar migrates
    // to package:material_ui (the bridge is deprecated).
    // ignore: deprecated_member_use
    return MaterialUiCompatibilityBridge(
      child: legacy.Material(
        type: legacy.MaterialType.transparency,
        child: TableCalendar<Occurrence>(
          firstDay: DateTime(2000),
          lastDay: DateTime(2100, 12, 31),
          focusedDay: focusedDay,
          currentDay: DateTime.now(),
          startingDayOfWeek: StartingDayOfWeek.monday,
          calendarFormat: _formats[span]!,
          onFormatChanged: (format) => onSpanChanged(
            _formats.entries.firstWhere((e) => e.value == format).key,
          ),
          selectedDayPredicate: (day) => isSameDay(day, selectedDay),
          onDaySelected: (selected, _) => onDaySelected(selected),
          onPageChanged: onPageChanged,
          eventLoader: index.on,
          calendarStyle: CalendarStyle(
            todayDecoration: BoxDecoration(
              color: colors.primaryContainer,
              shape: BoxShape.circle,
            ),
            todayTextStyle: TextStyle(color: colors.onPrimaryContainer),
            selectedDecoration: BoxDecoration(
              color: colors.primary,
              shape: BoxShape.circle,
            ),
            selectedTextStyle: TextStyle(color: colors.onPrimary),
          ),
          calendarBuilders: CalendarBuilders<Occurrence>(
            markerBuilder: (context, day, occurrences) {
              if (occurrences.isEmpty) return null;
              return Positioned(
                bottom: 2,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final occurrence in occurrences.take(4))
                      OccurrenceMarker(occurrence: occurrence),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// One day marker (see [CalendarView]).
class OccurrenceMarker extends StatelessWidget {
  const new({required this.occurrence, super.key});

  final Occurrence occurrence;

  @override
  Widget build(BuildContext context) {
    final color = occurrenceColor(occurrence, Theme.of(context).colorScheme);
    if (occurrence.kind == EventKind.birthday) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 1),
        child: Text('🎂', style: TextStyle(fontSize: 9)),
      );
    }
    return Container(
      width: 7,
      height: 7,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: occurrence.isRecurring ? null : color,
        border: occurrence.isRecurring
            ? Border.all(color: color, width: 1.5)
            : null,
      ),
    );
  }
}
