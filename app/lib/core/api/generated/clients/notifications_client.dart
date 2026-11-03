// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/push_config.dart';
import '../models/push_subscription_write.dart';
import '../models/unsubscribed.dart';

part 'notifications_client.g.dart';

@RestApi()
abstract class NotificationsClient {
  factory NotificationsClient(Dio dio, {String? baseUrl}) = _NotificationsClient;

  /// Unsubscribe.
  ///
  /// Public: turns off one kind of notification with the token from an email's unsubscribe.
  /// link. Mail apps call it too (RFC 8058 one-click: a form body, which is ignored).
  @POST('/api/v1/notifications/unsubscribe')
  Future<Unsubscribed> unsubscribe({
    @Query('token') required String token,
  });

  /// Get Push Config
  @GET('/api/v1/push/config')
  Future<PushConfig> getPushConfig();

  /// Save Push Subscription.
  ///
  /// Turns push on for this browser (or refreshes its keys).
  @PUT('/api/v1/me/push-subscription')
  Future<void> savePushSubscription({
    @Body() required PushSubscriptionWrite body,
  });

  /// Delete Push Subscription.
  ///
  /// Turns push off for this browser. Idempotent.
  @DELETE('/api/v1/me/push-subscription')
  Future<void> deletePushSubscription({
    @Query('endpoint') required String endpoint,
  });
}
