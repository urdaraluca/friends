// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/calendar_response.dart';
import '../models/event.dart';
import '../models/event_kind.dart';
import '../models/event_update.dart';
import '../models/event_write.dart';

part 'events_client.g.dart';

@RestApi()
abstract class EventsClient {
  factory EventsClient(Dio dio, {String? baseUrl}) = _EventsClient;

  /// Get Group Calendar.
  ///
  /// Occurrences in ``[from, to)``, sorted: by local start date in ``tz``, all-day before.
  /// timed, then start, title and key. ``category_id`` also matches its subcategories and leaves.
  /// member birthdays out.
  ///
  /// [from] - First day (inclusive).
  ///
  /// [to] - Last day (exclusive); at most 400 days after `from`.
  ///
  /// [tz] - IANA timezone for the range and the order; missing or invalid means your own (the response's `tz` says which was used).
  ///
  /// [kinds] - Repeat the key for several. Omitted: every kind. `birthday` also covers member birthdays.
  @GET('/api/v1/groups/{group_id}/calendar')
  Future<CalendarResponse> getGroupCalendar({
    @Path('group_id') required String groupId,
    @Query('from') required DateTime from,
    @Query('to') required DateTime to,
    @Query('tz') String? tz,
    @Query('kinds') List<EventKind>? kinds,
    @Query('category_id') String? categoryId,
  });

  /// Create Event.
  ///
  /// Any member. Linking an activity in ``idea`` or ``planning`` makes it ``scheduled``.
  @POST('/api/v1/groups/{group_id}/events')
  Future<Event> createEvent({
    @Path('group_id') required String groupId,
    @Body() required EventWrite body,
  });

  /// Get Event.
  ///
  /// The series definition, with its cancelled occurrence keys.
  @GET('/api/v1/events/{event_id}')
  Future<Event> getEvent({
    @Path('event_id') required String eventId,
  });

  /// Update Event.
  ///
  /// Edits the whole series; send the ``version`` you last read. Changing the start, the.
  /// all-day flag, the timezone or the rule restores every cancelled occurrence. The creator,.
  /// the linked activity's owner or an admin.
  @PUT('/api/v1/events/{event_id}')
  Future<Event> updateEvent({
    @Path('event_id') required String eventId,
    @Body() required EventUpdate body,
  });

  /// Delete Event.
  ///
  /// The whole series. The creator, the linked activity's owner or an admin.
  @DELETE('/api/v1/events/{event_id}')
  Future<void> deleteEvent({
    @Path('event_id') required String eventId,
  });

  /// Cancel Occurrence.
  ///
  /// Cancels one occurrence (idempotent). ``occurrence_key``: ``YYYYMMDDTHHMMSSZ`` (timed) or.
  /// ``YYYYMMDD`` (all-day, birthdays). Not for one-time events: delete the event instead.
  @DELETE('/api/v1/events/{event_id}/occurrences/{occurrence_key}')
  Future<void> cancelOccurrence({
    @Path('occurrence_key') required String occurrenceKey,
    @Path('event_id') required String eventId,
  });

  /// Restore Occurrence.
  ///
  /// Restores a cancelled occurrence (idempotent).
  @POST('/api/v1/events/{event_id}/occurrences/{occurrence_key}/restore')
  Future<void> restoreOccurrence({
    @Path('occurrence_key') required String occurrenceKey,
    @Path('event_id') required String eventId,
  });
}
