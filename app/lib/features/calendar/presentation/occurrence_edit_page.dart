import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_error_messages.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/api_instant.dart';
import 'package:friends/core/api/date_only.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/widgets/form_widgets.dart';
import 'package:friends/features/calendar/data/calendar_providers.dart';
import 'package:friends/features/calendar/presentation/event_detail_screen.dart';
import 'package:friends/features/groups/presentation/widgets/group_themed.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// Opens the editor for [event]'s occurrence [occurrenceKey].
Future<void> openOccurrenceEdit(
  BuildContext context, {
  required String groupId,
  required Event event,
  required String occurrenceKey,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) => GroupThemed(
        groupId: groupId,
        child: OccurrenceEditPage(event: event, occurrenceKey: occurrenceKey),
      ),
    ),
  );
}

/// Another title or time for one occurrence of a recurring event, the
/// rest of the series unchanged (contract section 5.6). Saving values equal
/// to the series' takes the occurrence back to the series.
class OccurrenceEditPage extends ConsumerStatefulWidget {
  const new({required this.event, required this.occurrenceKey, super.key});

  final Event event;
  final String occurrenceKey;

  @override
  ConsumerState<OccurrenceEditPage> createState() => _OccurrenceEditPageState();
}

class _OccurrenceEditPageState extends ConsumerState<OccurrenceEditPage> {
  late final _title = TextEditingController(
    text: occurrenceTitle(widget.event, widget.occurrenceKey),
  );
  late final OccurrenceTimes _series = occurrenceTimes(
    widget.event,
    widget.occurrenceKey,
    series: true,
  );
  late final OccurrenceTimes _current = occurrenceTimes(
    widget.event,
    widget.occurrenceKey,
  );

  /// Timed: local start and end.
  late DateTime? _start = _current.start?.toLocal();
  late DateTime? _end = _current.end?.toLocal();

  /// All-day: local first and last days.
  late DateTime? _firstDay = _local(_current.startDate);
  late DateTime? _lastDay = _local(_current.endDate);

  String? _error;
  bool _saving = false;

  static DateTime? _local(DateTime? date) =>
      date == null ? null : DateTime(date.year, date.month, date.day);

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDay(DateTime initial) => showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );

  Future<void> _pickStart() async {
    final start = _start!;
    final day = await _pickDay(start);
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(start),
    );
    if (time == null) return;
    final next = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    // The length stays the same.
    setState(() {
      _end = next.add(_end!.difference(start));
      _start = next;
    });
  }

  Future<void> _pickEnd() async {
    final end = _end!;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(end),
    );
    if (time == null) return;
    final start = _start!;
    var next = DateTime(
      start.year,
      start.month,
      start.day,
      time.hour,
      time.minute,
    );
    // An end before the start is the next day ("until 01:00").
    if (!next.isAfter(start)) {
      next = DateTime(
        next.year,
        next.month,
        next.day + 1,
        next.hour,
        next.minute,
      );
    }
    setState(() => _end = next);
  }

  Future<void> _pickFirstDay() async {
    final first = _firstDay!;
    final day = await _pickDay(first);
    if (day == null) return;
    final length = _lastDay!.difference(first).inDays;
    setState(() {
      _firstDay = day;
      _lastDay = DateTime(day.year, day.month, day.day + length);
    });
  }

  Future<void> _pickLastDay() async {
    final day = await _pickDay(_lastDay!);
    if (day != null) setState(() => _lastDay = day);
  }

  Future<void> _save() async {
    final event = widget.event;
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Enter a title.');
      return;
    }
    final newTitle = title == event.title ? null : title;
    OccurrenceEditWrite body;
    var moved = false;
    if (_start case final start?) {
      final end = _end!;
      if (!end.isAfter(start)) {
        setState(() => _error = 'The end must be after the start.');
        return;
      }
      moved =
          !start.isAtSameMomentAs(_series.start!) ||
          !end.isAtSameMomentAs(_series.end!);
      body = OccurrenceEditWrite(
        title: newTitle,
        startsAt: moved ? ApiInstant.of(start) : null,
        endsAt: moved ? ApiInstant.of(end) : null,
      );
    } else {
      final first = DateOnly.from(_firstDay!);
      final last = DateOnly.from(_lastDay!);
      if (DateOnly.compare(last, first) < 0) {
        setState(() => _error = 'The last day is before the first.');
        return;
      }
      moved =
          !DateOnly.isSameDay(first, _series.startDate!) ||
          !DateOnly.isSameDay(last, _series.endDate!);
      body = OccurrenceEditWrite(
        title: newTitle,
        startDate: moved ? first : null,
        endDate: moved ? last : null,
      );
    }
    final controller = ref.read(eventsControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final edited = occurrenceEdit(event, widget.occurrenceKey) != null;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (newTitle == null && !moved) {
        // Nothing differs from the series: back to it.
        if (edited) {
          await controller.restoreOccurrence(event, widget.occurrenceKey);
        }
      } else {
        await controller.editOccurrence(event, widget.occurrenceKey, body);
      }
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Changed for this time only')),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayFormat = DateFormat('EEE d MMM y');
    final timeFormat = DateFormat.Hm();
    final start = _start;
    final end = _end;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Change this occurrence'),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => unawaited(_save()),
            child: const Text('Save'),
          ),
        ],
      ),
      body: FormPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Only this time changes; the rest of the series stays as it '
              'is.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              inputFormatters: [LengthLimitingTextInputFormatter(120)],
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 16),
            if (start != null && end != null) ...[
              _PickerTile(
                label: 'Starts',
                text: '${dayFormat.format(start)}, ${timeFormat.format(start)}',
                onTap: () => unawaited(_pickStart()),
              ),
              const SizedBox(height: 12),
              _PickerTile(
                label: 'Ends',
                text: DateUtils.isSameDay(start, end)
                    ? timeFormat.format(end)
                    : '${dayFormat.format(end)}, ${timeFormat.format(end)}',
                onTap: () => unawaited(_pickEnd()),
              ),
            ] else ...[
              _PickerTile(
                label: 'First day',
                text: dayFormat.format(_firstDay!),
                onTap: () => unawaited(_pickFirstDay()),
              ),
              const SizedBox(height: 12),
              _PickerTile(
                label: 'Last day',
                text: dayFormat.format(_lastDay!),
                onTap: () => unawaited(_pickLastDay()),
              ),
            ],
            if (_error case final error?) ...[
              const SizedBox(height: 16),
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const new({required this.label, required this.text, required this.onTap});

  final String label;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.edit_calendar_outlined),
        ),
        child: Text(text),
      ),
    );
  }
}
