// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'notification_kind.dart';

part 'unsubscribed.freezed.dart';
part 'unsubscribed.g.dart';

@Freezed()
abstract class Unsubscribed with _$Unsubscribed {
  const factory Unsubscribed({
    required NotificationKind kind,
  }) = _Unsubscribed;
  
  factory Unsubscribed.fromJson(Map<String, Object?> json) => _$UnsubscribedFromJson(json);
}
