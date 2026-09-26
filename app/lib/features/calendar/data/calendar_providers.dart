import 'package:flutter/foundation.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/api_providers.dart';
import 'package:friends/core/api/date_only.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/device/device_info.dart';
import 'package:friends/features/backlog/data/backlog_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'calendar_providers.g.dart';

/// A calendar request: the dates `[from, to)` (UTC midnights, `DateOnly`),
/// the kinds (empty = all) and the category (with its subcategories).
@immutable
class CalendarQuery {
  const new({
    required this.from,
    required this.to,
    this.kinds = const {},
    this.categoryId,
  });

  final DateTime from;

  /// Exclusive.
  final DateTime to;
  final Set<EventKind> kinds;
  final String? categoryId;

  @override
  bool operator ==(Object other) =>
      other is CalendarQuery &&
      DateOnly.format(other.from) == DateOnly.format(from) &&
      DateOnly.format(other.to) == DateOnly.format(to) &&
      setEquals(other.kinds, kinds) &&
      other.categoryId == categoryId;

  @override
  int get hashCode => Object.hash(
    DateOnly.format(from),
    DateOnly.format(to),
    Object.hashAllUnordered(kinds),
    categoryId,
  );
}

/// A group's occurrences for [query], in the device's timezone
/// (`GET /groups/{id}/calendar`, contract section 5.5). The server expands
/// the recurrence; the client only lays the occurrences out.
@riverpod
Future<CalendarResponse> calendar(
  Ref ref,
  String groupId,
  CalendarQuery query,
) async {
  ref.watch(currentUserIdProvider);
  final tz = await ref.watch(deviceTimezoneProvider.future);
  final client = ref.watch(eventsClientProvider);
  return await apiCall(
    () => client.getGroupCalendar(
      groupId: groupId,
      from: query.from,
      to: query.to,
      tz: tz,
      kinds: query.kinds.isEmpty
          ? null
          : [
              for (final kind in EventKind.$valuesDefined)
                if (query.kinds.contains(kind)) kind,
            ],
      categoryId: query.categoryId,
    ),
  );
}

/// One event series (`GET /events/{id}`).
@riverpod
Future<Event> event(Ref ref, String eventId) {
  ref.watch(currentUserIdProvider);
  final client = ref.watch(eventsClientProvider);
  return apiCall(() => client.getEvent(eventId: eventId));
}

/// The calendar's filters for a group: the kinds shown (empty = all) and a
/// category.
@immutable
class CalendarFilters {
  const new({this.kinds = const {}, this.categoryId});

  final Set<EventKind> kinds;
  final String? categoryId;

  CalendarFilters copyWith({
    Set<EventKind>? kinds,
    String? Function()? categoryId,
  }) => CalendarFilters(
    kinds: kinds ?? this.kinds,
    categoryId: categoryId == null ? this.categoryId : categoryId(),
  );

  @override
  bool operator ==(Object other) =>
      other is CalendarFilters &&
      setEquals(other.kinds, kinds) &&
      other.categoryId == categoryId;

  @override
  int get hashCode => Object.hash(Object.hashAllUnordered(kinds), categoryId);
}

@Riverpod(keepAlive: true)
class CalendarFilter extends _$CalendarFilter {
  @override
  CalendarFilters build(String groupId) {
    ref.watch(currentUserIdProvider);
    return const CalendarFilters();
  }

  // A setter-like method: Riverpod notifiers expose state changes as calls.
  // ignore: use_setters_to_change_properties
  void set(CalendarFilters filters) => state = filters;
}

/// How many weeks the calendar shows.
enum CalendarSpan { month, twoWeeks, week }

/// Remembers the calendar's span on this device.
class CalendarSpanStore {
  new([SharedPreferencesAsync? prefs]) : _prefs = prefs;

  static const _key = 'friends.calendar_span';

  SharedPreferencesAsync? _prefs;

  SharedPreferencesAsync get _store => _prefs ??= SharedPreferencesAsync();

  /// The saved span, or null (best effort: storage failures read as none).
  Future<CalendarSpan?> read() async {
    try {
      final name = await _store.getString(_key);
      return CalendarSpan.values.where((s) => s.name == name).firstOrNull;
    } on Object {
      return null;
    }
  }

  Future<void> write(CalendarSpan span) async {
    try {
      await _store.setString(_key, span.name);
    } on Object {
      // Best effort.
    }
  }
}

@Riverpod(keepAlive: true)
CalendarSpanStore calendarSpanStore(Ref ref) => CalendarSpanStore();

/// The calendar's span, loaded from and saved to [calendarSpanStoreProvider].
@Riverpod(keepAlive: true)
class CalendarSpanSetting extends _$CalendarSpanSetting {
  @override
  Future<CalendarSpan> build() async =>
      await ref.read(calendarSpanStoreProvider).read() ?? CalendarSpan.month;

  Future<void> set(CalendarSpan span) async {
    state = AsyncData(span);
    await ref.read(calendarSpanStoreProvider).write(span);
  }
}

/// Every event mutation (contract section 8.8). Each method throws
/// `ApiException`s; on success it refreshes the calendar, the event and the
/// backlog (a linked idea becomes scheduled; activities list their next
/// occurrence).
@Riverpod(keepAlive: true)
class EventsController extends _$EventsController {
  @override
  void build() {}

  EventsClient get _client => ref.read(eventsClientProvider);

  void _changed({String? eventId, Iterable<String?> activityIds = const []}) {
    ref.invalidate(calendarProvider);
    if (eventId != null) ref.invalidate(eventProvider(eventId));
    final backlog = ref.read(backlogControllerProvider.notifier);
    final ids = activityIds.nonNulls.toSet();
    if (ids.isEmpty) {
      backlog.activitiesChanged();
    } else {
      for (final id in ids) {
        backlog.activitiesChanged(activityId: id);
      }
    }
  }

  /// `POST /groups/{id}/events`. Linking an idea or planning activity makes
  /// it scheduled.
  Future<Event> create(String groupId, EventWrite body) async {
    final event = await apiCall(
      () => _client.createEvent(groupId: groupId, body: body),
    );
    _changed(eventId: event.id, activityIds: [event.activityId]);
    return event;
  }

  /// `PUT /events/{id}`: the whole series, with the `version` last read
  /// (`409 version_conflict`). Changing the start, the dates, all-day, the
  /// timezone or the rule deletes the cancelled occurrences.
  Future<Event> update(Event event, EventUpdate body) async {
    final updated = await apiCall(
      () => _client.updateEvent(eventId: event.id, body: body),
    );
    _changed(
      eventId: event.id,
      activityIds: [event.activityId, updated.activityId],
    );
    return updated;
  }

  /// `DELETE /events/{id}`: the whole series.
  Future<void> delete(Event event) async {
    await apiCall(() => _client.deleteEvent(eventId: event.id));
    _changed(eventId: event.id, activityIds: [event.activityId]);
  }

  /// `DELETE /events/{id}/occurrences/{key}` (idempotent).
  Future<void> cancelOccurrence(Event event, String occurrenceKey) async {
    await apiCall(
      () => _client.cancelOccurrence(
        eventId: event.id,
        occurrenceKey: occurrenceKey,
      ),
    );
    _changed(eventId: event.id, activityIds: [event.activityId]);
  }

  /// `POST /events/{id}/occurrences/{key}/restore` (idempotent).
  Future<void> restoreOccurrence(Event event, String occurrenceKey) async {
    await apiCall(
      () => _client.restoreOccurrence(
        eventId: event.id,
        occurrenceKey: occurrenceKey,
      ),
    );
    _changed(eventId: event.id, activityIds: [event.activityId]);
  }
}
