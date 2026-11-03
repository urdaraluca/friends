// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'push_keys.dart';

part 'push_subscription_write.freezed.dart';
part 'push_subscription_write.g.dart';

/// A browser's ``PushSubscription.toJSON()``, minus ``expirationTime``.
@Freezed()
abstract class PushSubscriptionWrite with _$PushSubscriptionWrite {
  const factory PushSubscriptionWrite({
    required String endpoint,
    required PushKeys keys,
  }) = _PushSubscriptionWrite;
  
  factory PushSubscriptionWrite.fromJson(Map<String, Object?> json) => _$PushSubscriptionWriteFromJson(json);
}
