// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'push_config.freezed.dart';
part 'push_config.g.dart';

@Freezed()
abstract class PushConfig with _$PushConfig {
  const factory PushConfig({
    @JsonKey(name: 'public_key')
    required String? publicKey,
  }) = _PushConfig;
  
  factory PushConfig.fromJson(Map<String, Object?> json) => _$PushConfigFromJson(json);
}
