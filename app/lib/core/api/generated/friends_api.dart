// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';

import 'clients/health_client.dart';
import 'clients/auth_client.dart';
import 'clients/users_client.dart';
import 'clients/groups_client.dart';
import 'clients/invites_client.dart';
import 'clients/categories_client.dart';
import 'clients/activities_client.dart';
import 'clients/wheel_client.dart';
import 'clients/polls_client.dart';
import 'clients/events_client.dart';
import 'clients/availability_client.dart';
import 'clients/recap_client.dart';

/// Friends API `v1`
class FriendsApi {
  FriendsApi(
    Dio dio, {
    String? baseUrl,
  })  : _dio = dio,
        _baseUrl = baseUrl;

  final Dio _dio;
  final String? _baseUrl;

  static String get version => '1';

  HealthClient? _health;
  AuthClient? _auth;
  UsersClient? _users;
  GroupsClient? _groups;
  InvitesClient? _invites;
  CategoriesClient? _categories;
  ActivitiesClient? _activities;
  WheelClient? _wheel;
  PollsClient? _polls;
  EventsClient? _events;
  AvailabilityClient? _availability;
  RecapClient? _recap;

  HealthClient get health => _health ??= HealthClient(_dio, baseUrl: _baseUrl);

  AuthClient get auth => _auth ??= AuthClient(_dio, baseUrl: _baseUrl);

  UsersClient get users => _users ??= UsersClient(_dio, baseUrl: _baseUrl);

  GroupsClient get groups => _groups ??= GroupsClient(_dio, baseUrl: _baseUrl);

  InvitesClient get invites => _invites ??= InvitesClient(_dio, baseUrl: _baseUrl);

  CategoriesClient get categories => _categories ??= CategoriesClient(_dio, baseUrl: _baseUrl);

  ActivitiesClient get activities => _activities ??= ActivitiesClient(_dio, baseUrl: _baseUrl);

  WheelClient get wheel => _wheel ??= WheelClient(_dio, baseUrl: _baseUrl);

  PollsClient get polls => _polls ??= PollsClient(_dio, baseUrl: _baseUrl);

  EventsClient get events => _events ??= EventsClient(_dio, baseUrl: _baseUrl);

  AvailabilityClient get availability => _availability ??= AvailabilityClient(_dio, baseUrl: _baseUrl);

  RecapClient get recap => _recap ??= RecapClient(_dio, baseUrl: _baseUrl);
}
