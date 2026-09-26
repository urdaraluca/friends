// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/account_deletion.dart';
import '../models/calendar_response.dart';
import '../models/event_kind.dart';
import '../models/me.dart';
import '../models/me_update.dart';
import '../models/my_availability.dart';
import '../models/my_availability_update.dart';
import '../models/password_change.dart';
import '../models/token_pair.dart';

part 'users_client.g.dart';

@RestApi()
abstract class UsersClient {
  factory UsersClient(Dio dio, {String? baseUrl}) = _UsersClient;

  /// Get Me
  @GET('/api/v1/me')
  Future<Me> getMe();

  /// Update Me
  @PUT('/api/v1/me')
  Future<Me> updateMe({
    @Body() required MeUpdate body,
  });

  /// Change Password.
  ///
  /// Changes the password, signs out all other sessions and returns new tokens for this one.
  @POST('/api/v1/me/password')
  Future<TokenPair> changePassword({
    @Body() required PasswordChange body,
  });

  /// Delete Account.
  ///
  /// Deletes the account: owned groups go to the oldest admin (or member), or are deleted if.
  /// you are alone in them; you leave every group; your profile is anonymized.
  @POST('/api/v1/me/deletion')
  Future<void> deleteAccount({
    @Body() required AccountDeletion body,
  });

  /// Get My Calendar.
  ///
  /// Occurrences across all your groups in ``[from, to)``. Member birthdays appear once per.
  /// person (``group_id`` null) if they show them in at least one group you share.
  ///
  /// [from] - First day (inclusive).
  ///
  /// [to] - Last day (exclusive); at most 400 days after `from`.
  ///
  /// [tz] - IANA timezone for the range and the order; missing or invalid means your own (the response's `tz` says which was used).
  ///
  /// [kinds] - Repeat the key for several. Omitted: every kind. `birthday` also covers member birthdays.
  @GET('/api/v1/me/calendar')
  Future<CalendarResponse> getMyCalendar({
    @Query('from') required DateTime from,
    @Query('to') required DateTime to,
    @Query('tz') String? tz,
    @Query('kinds') List<EventKind>? kinds,
  });

  /// Get My Availability.
  ///
  /// My answers in ``[from, to)`` (at most 92 days), by date then slot. They show in every group.
  /// I'm in.
  ///
  /// [from] - First day (inclusive).
  ///
  /// [to] - Last day (exclusive); at most 92 days after `from`.
  @GET('/api/v1/me/availability')
  Future<MyAvailability> getMyAvailability({
    @Query('from') required DateTime from,
    @Query('to') required DateTime to,
  });

  /// Update My Availability.
  ///
  /// Replaces my answers in ``[from_date, to_date)``: a slot left out becomes unknown.
  @PUT('/api/v1/me/availability')
  Future<MyAvailability> updateMyAvailability({
    @Body() required MyAvailabilityUpdate body,
  });
}
