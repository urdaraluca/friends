// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'notification_settings.freezed.dart';
part 'notification_settings.g.dart';

/// Which notifications I get (contract section 18.4), by push and, to a verified address,.
/// by email.
@Freezed()
abstract class NotificationSettings with _$NotificationSettings {
  const factory NotificationSettings({
    required bool polls,
    required bool wheel,
    required bool reminders,
    @Default(true)
    bool members,
    @Default(true)
    bool plans,
    @Default(false)
    bool email,
  }) = _NotificationSettings;
  
  factory NotificationSettings.fromJson(Map<String, Object?> json) => _$NotificationSettingsFromJson(json);
}
