import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/api_instant.dart';
import 'package:friends/core/api/date_only.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/forms/field_errors.dart';
import 'package:friends/core/forms/validators.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/core/widgets/form_widgets.dart';
import 'package:friends/core/widgets/version_conflict_dialog.dart';
import 'package:friends/features/backlog/data/backlog_providers.dart';
import 'package:friends/features/backlog/domain/category_index.dart';
import 'package:friends/features/backlog/presentation/widgets/category_picker.dart';
import 'package:friends/features/backlog/presentation/widgets/category_visuals.dart';
import 'package:friends/features/calendar/data/calendar_providers.dart';
import 'package:friends/features/calendar/domain/rrule_spec.dart';
import 'package:friends/features/calendar/presentation/widgets/recurrence_picker.dart';
import 'package:friends/features/groups/data/group_providers.dart';
import 'package:friends/features/groups/presentation/widgets/group_themed.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// Creates an event (`/groups/:groupId/calendar/events/new?activityId=&date=`)
/// or edits one (`…/events/:eventId/edit`).
class EventFormScreen extends ConsumerWidget {
  /// The new-event form, starting on [date] and linked to [activityId]
  /// ("Schedule it").
  const new create({
    required this.groupId,
    this.activityId,
    this.date,
    super.key,
  }) : eventId = null;

  /// The edit form of [eventId].
  const new edit({
    required this.groupId,
    required String this.eventId,
    super.key,
  }) : activityId = null,
       date = null;

  final String groupId;
  final String? eventId;
  final String? activityId;
  final DateTime? date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(groupProvider(groupId));
    final categories = ref.watch(categoryIndexProvider(groupId));
    final event = eventId == null
        ? const AsyncData<Event?>(null)
        : ref.watch(eventProvider(eventId!)).whenData<Event?>((e) => e);
    final linkedId = event.value?.activityId ?? activityId;
    final activity = linkedId == null
        ? const AsyncData<Activity?>(null)
        : ref.watch(activityProvider(linkedId)).whenData<Activity?>((a) => a);

    final all = switch ((group, categories, event)) {
      (AsyncError(:final error, :final stackTrace), _, _) ||
      (_, AsyncError(:final error, :final stackTrace), _) ||
      (
        _,
        _,
        AsyncError(:final error, :final stackTrace),
      ) => AsyncError<_FormData>(error, stackTrace),
      (
        AsyncData(value: final group),
        AsyncData(value: final categories),
        AsyncData(value: final event),
      ) =>
        AsyncData(_FormData(group, categories, event)),
      _ => const AsyncLoading<_FormData>(),
    };

    return GroupThemed(
      groupId: groupId,
      child: Scaffold(
        appBar: AppBar(
          title: Text(eventId == null ? 'New event' : 'Edit event'),
        ),
        body: AsyncValueView(
          value: all,
          onRetry: () {
            ref
              ..invalidate(groupProvider(groupId))
              ..invalidate(categoriesProvider(groupId));
            if (eventId != null) ref.invalidate(eventProvider(eventId!));
          },
          data: (data) => FormPage(
            maxWidth: 640,
            child: EventForm(
              key: ValueKey(data.event?.version),
              groupId: groupId,
              group: data.group,
              categories: data.categories,
              event: data.event,
              activity: activity.value,
              date: date,
            ),
          ),
        ),
      ),
    );
  }
}

class _FormData {
  const new(this.group, this.categories, this.event);

  final Group group;
  final CategoryIndex categories;
  final Event? event;
}

/// The fields of an event (contract section 5.8, `EventWrite`).
class EventForm extends ConsumerStatefulWidget {
  const new({
    required this.groupId,
    required this.group,
    required this.categories,
    this.event,
    this.activity,
    this.date,
    super.key,
  });

  final String groupId;
  final Group group;
  final CategoryIndex categories;

  /// The event being edited, or null to create one.
  final Event? event;

  /// The linked activity (to schedule), if any.
  final Activity? activity;

  /// The day a new event starts on.
  final DateTime? date;

  @override
  ConsumerState<EventForm> createState() => _EventFormState();
}

class _EventFormState extends ConsumerState<EventForm> with ServerErrorsMixin {
  static const _fields = {
    'kind',
    'title',
    'description',
    'all_day',
    'starts_at',
    'ends_at',
    'start_date',
    'end_date',
    'timezone',
    'rrule',
    'category_id',
    'activity_id',
    'location_name',
    'address',
  };

  final _formKey = GlobalKey<FormState>();
  late final Event? _event = widget.event;
  late EventKind _kind = _event?.kind ?? EventKind.oneTime;
  late final _title = TextEditingController(
    text: _event?.title ?? widget.activity?.title,
  );
  late final _description = TextEditingController(text: _event?.description);
  late final _location = TextEditingController(
    text: _event?.locationName ?? widget.activity?.locationName,
  );
  late final _address = TextEditingController(
    text: _event?.address ?? widget.activity?.address,
  );
  late final _timezone = TextEditingController(
    text: _event?.timezone ?? widget.group.timezone,
  );
  late bool _allDay = _event?.allDay ?? false;

  /// Local start and end (timed), or dates at local midnight (all-day).
  late DateTime _start;
  late DateTime _end;
  late String? _categoryId = _event?.categoryId ?? widget.activity?.categoryId;
  late String? _activityId = _event?.activityId ?? widget.activity?.id;
  late RecurrenceSpec _spec;
  String? _ruleError;
  bool _saving = false;

  bool get _creating => _event == null;

  @override
  void initState() {
    super.initState();
    final event = _event;
    if (event == null) {
      final day = widget.date ?? DateTime.now();
      _start = DateTime(day.year, day.month, day.day, 19);
      _end = _start.add(const Duration(hours: 2));
    } else if (event.allDay) {
      final start = event.startDate!;
      final end = event.endDate ?? start;
      _start = DateTime(start.year, start.month, start.day);
      _end = DateTime(end.year, end.month, end.day);
    } else {
      _start = event.startsAt!.toLocal();
      _end = event.endsAt!.toLocal();
    }
    final rule = event?.rrule;
    _spec =
        (rule == null || event?.kind != EventKind.recurring
            ? null
            : RecurrenceSpec.tryParse(rule)) ??
        RecurrenceSpec.startingOn(RepeatFrequency.weekly, _start);
  }

  @override
  void dispose() {
    for (final c in [_title, _description, _location, _address, _timezone]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isAllDay => _kind == EventKind.birthday || _allDay;

  static String? _optional(TextEditingController c) {
    final value = c.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<DateTime?> _pickDate(DateTime initial) => showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: _kind == EventKind.birthday ? DateTime(1900) : DateTime(2000),
    lastDate: DateTime(2100),
  );

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await _pickDate(initial);
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  /// The rule to send, or null. Checked here first (contract section 5.2).
  String? _rule() {
    if (_kind != EventKind.recurring) return null;
    final rule = _spec.toRule(allDay: _isAllDay);
    try {
      return canonicalizeRRule(
        rule,
        startDate: _start,
        allDay: _isAllDay,
        startsAtUtc: _isAllDay ? null : ApiInstant.of(_start),
      );
    } on InvalidRRule catch (error) {
      setState(() => _ruleError = rruleReasonMessage(error.reason));
      return null;
    }
  }

  EventWrite _write(String? rule) => EventWrite(
    kind: _kind,
    title: _title.text.trim(),
    description: _optional(_description),
    allDay: _isAllDay,
    startsAt: _isAllDay ? null : ApiInstant.of(_start),
    endsAt: _isAllDay ? null : ApiInstant.of(_end),
    startDate: _isAllDay ? DateOnly.from(_start) : null,
    endDate: _isAllDay && _kind != EventKind.birthday
        ? DateOnly.from(_end)
        : null,
    timezone: _optional(_timezone),
    rrule: rule,
    categoryId: _categoryId,
    activityId: _activityId,
    locationName: _optional(_location),
    address: _optional(_address),
  );

  /// Whether saving [body] deletes the cancelled occurrences (a timing or
  /// rule change, contract section 5.6).
  bool _clearsExceptions(Event event, EventWrite body) =>
      event.cancelledOccurrenceKeys.isNotEmpty &&
      (body.allDay != event.allDay ||
          body.timezone != event.timezone ||
          body.rrule != event.rrule ||
          body.startsAt != event.startsAt?.toUtc() ||
          (body.startDate != null &&
              !DateOnly.isSameDay(body.startDate!, event.startDate!)));

  Future<void> _save() async {
    clearFormError();
    setState(() => _ruleError = null);
    if (!_formKey.currentState!.validate()) return;
    if (!_isAllDay && !_end.isAfter(_start)) {
      showServerError(
        const ProblemException(
          status: 422,
          code: ErrorCodes.validationError,
          errors: [
            FieldError(
              field: 'ends_at',
              message: 'The end must be after the start.',
              type: 'value_error',
            ),
          ],
        ),
        fields: _fields,
      );
      return;
    }
    final rule = _rule();
    if (_kind == EventKind.recurring && rule == null) return;
    final body = _write(rule);
    final event = _event;
    if (event != null && _clearsExceptions(event, body)) {
      final count = event.cancelledOccurrenceKeys.length;
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restore cancelled dates?'),
          content: Text(
            'Changing the time or the repeat pattern brings back the '
            '$count cancelled ${count == 1 ? 'occurrence' : 'occurrences'}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save anyway'),
            ),
          ],
        ),
      );
      if (go != true) return;
    }
    if (!mounted) return;
    setState(() => _saving = true);
    final controller = ref.read(eventsControllerProvider.notifier);
    final router = GoRouter.of(context);
    try {
      if (event == null) {
        final created = await controller.create(widget.groupId, body);
        unawaited(
          router.replace<void>(Routes.event(widget.groupId, created.id)),
        );
      } else {
        await controller.update(
          event,
          EventUpdate(
            kind: body.kind,
            title: body.title,
            allDay: body.allDay,
            version: event.version,
            description: body.description,
            startsAt: body.startsAt,
            endsAt: body.endsAt,
            startDate: body.startDate,
            endDate: body.endDate,
            timezone: body.timezone,
            rrule: body.rrule,
            categoryId: body.categoryId,
            activityId: body.activityId,
            locationName: body.locationName,
            address: body.address,
          ),
        );
        if (router.canPop()) {
          router.pop();
        } else {
          router.go(Routes.event(widget.groupId, event.id));
        }
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      switch (error) {
        case ProblemException(code: ErrorCodes.versionConflict):
          setState(() => _saving = false);
          await showVersionConflictDialog(context);
          ref.invalidate(eventProvider(event!.id));
          return;
        case ProblemException(code: ErrorCodes.invalidRrule, :final errors):
          setState(
            () => _ruleError = rruleReasonMessage(
              errors.isEmpty ? '' : errors.first.type,
            ),
          );
        default:
          showServerError(error, fields: _fields);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayFormat = DateFormat('EEE d MMM y');
    final timeFormat = DateFormat('EEE d MMM y, HH:mm');
    final birthday = _kind == EventKind.birthday;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (formError case final message?) ...[
            FormMessageBanner(message: message),
            const SizedBox(height: 16),
          ],
          SegmentedButton<EventKind>(
            segments: const [
              ButtonSegment(
                value: EventKind.oneTime,
                label: Text('Once'),
                icon: Icon(Icons.event),
              ),
              ButtonSegment(
                value: EventKind.recurring,
                label: Text('Repeats'),
                icon: Icon(Icons.repeat),
              ),
              ButtonSegment(
                value: EventKind.birthday,
                label: Text('Birthday'),
                icon: Icon(Icons.cake_outlined),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (selection) =>
                setState(() => _kind = selection.single),
          ),
          if (birthday)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                "For someone who isn't on Friends. Members' own birthdays "
                'come from their profiles.',
              ),
            ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _title,
            decoration: InputDecoration(
              labelText: birthday ? 'Whose birthday' : 'Title',
            ),
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            validator: Validators.required(
              birthday ? 'a name' : 'a title',
              max: 120,
            ),
            forceErrorText: serverError('title'),
            onChanged: (_) => clearServerError('title'),
          ),
          if (!birthday)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('All day'),
              value: _allDay,
              onChanged: (value) => setState(() {
                _allDay = value;
                if (value) {
                  _start = DateTime(_start.year, _start.month, _start.day);
                  _end = DateTime(_end.year, _end.month, _end.day);
                  if (_end.isBefore(_start)) _end = _start;
                } else {
                  _start = DateTime(_start.year, _start.month, _start.day, 19);
                  _end = _start.add(const Duration(hours: 2));
                }
              }),
            ),
          _DateTile(
            label: birthday ? 'Born on' : 'Starts',
            text: _isAllDay
                ? dayFormat.format(_start)
                : timeFormat.format(_start),
            error: serverError('starts_at') ?? serverError('start_date'),
            onTap: () async {
              final picked = _isAllDay
                  ? await _pickDate(_start)
                  : await _pickDateTime(_start);
              if (picked == null) return;
              clearServerError('starts_at');
              clearServerError('start_date');
              setState(() {
                if (_isAllDay) {
                  // Whole days (UTC midnights have no DST gaps).
                  final days = DateOnly.from(_end)
                      .difference(DateOnly.from(_start))
                      .inDays;
                  _end = DateTime(picked.year, picked.month, picked.day + days);
                } else {
                  _end = picked.add(_end.difference(_start));
                }
                _start = picked;
              });
            },
          ),
          if (!birthday)
            _DateTile(
              label: 'Ends',
              text: _isAllDay
                  ? dayFormat.format(_end)
                  : timeFormat.format(_end),
              error: serverError('ends_at') ?? serverError('end_date'),
              onTap: () async {
                final picked = _isAllDay
                    ? await _pickDate(_end)
                    : await _pickDateTime(_end);
                if (picked == null) return;
                clearServerError('ends_at');
                clearServerError('end_date');
                setState(() => _end = picked);
              },
            ),
          if (!_isAllDay)
            TextFormField(
              controller: _timezone,
              decoration: const InputDecoration(
                labelText: 'Timezone',
                helperText:
                    "The time zone it repeats in (the group's by "
                    'default)',
              ),
              forceErrorText: serverError('timezone'),
              onChanged: (_) => clearServerError('timezone'),
            ),
          if (_kind == EventKind.recurring) ...[
            const SizedBox(height: 16),
            Text('Repeats', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            RecurrencePicker(
              spec: _spec,
              start: _start,
              error: _ruleError ?? serverError('rrule'),
              onChanged: (spec) => setState(() {
                _spec = spec;
                _ruleError = null;
                clearServerError('rrule');
              }),
            ),
          ],
          const SizedBox(height: 8),
          InputDecorator(
            decoration: InputDecoration(
              labelText: 'Category',
              errorText: serverError('category_id'),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: CategoryLabel(
                index: widget.categories,
                categoryId: _categoryId,
              ),
              trailing: const Icon(Icons.arrow_drop_down),
              onTap: () async {
                final choice = await showCategoryPicker(
                  context,
                  index: widget.categories,
                  selectedId: _categoryId,
                  noneLabel: 'No category',
                );
                if (choice is PickedCategory) {
                  setState(() => _categoryId = choice.id);
                }
              },
            ),
          ),
          if (_activityId != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lightbulb_outline),
              title: Text(widget.activity?.title ?? 'A backlog idea'),
              subtitle: Text(
                _creating
                    ? 'Scheduling this idea marks it as scheduled'
                    : 'Linked idea',
              ),
              trailing: IconButton(
                tooltip: 'Unlink the idea',
                icon: const Icon(Icons.link_off),
                onPressed: () => setState(() => _activityId = null),
              ),
            ),
          TextFormField(
            controller: _location,
            decoration: const InputDecoration(labelText: 'Place'),
            maxLength: 120,
            forceErrorText: serverError('location_name'),
          ),
          TextFormField(
            controller: _address,
            decoration: const InputDecoration(labelText: 'Address'),
            maxLength: 300,
            forceErrorText: serverError('address'),
          ),
          TextFormField(
            controller: _description,
            decoration: const InputDecoration(labelText: 'Description'),
            minLines: 2,
            maxLines: 6,
            maxLength: 5000,
            forceErrorText: serverError('description'),
          ),
          const SizedBox(height: 16),
          SubmitButton(
            label: _creating ? 'Add to calendar' : 'Save',
            busy: _saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const new({
    required this.label,
    required this.text,
    required this.onTap,
    this.error,
  });

  final String label;
  final String text;
  final VoidCallback onTap;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label, errorText: error),
      child: InkWell(onTap: onTap, child: Text(text)),
    );
  }
}
