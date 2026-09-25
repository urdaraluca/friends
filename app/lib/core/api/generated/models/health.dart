// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'health_db.dart';
import 'health_status.dart';

part 'health.freezed.dart';
part 'health.g.dart';

@Freezed()
abstract class Health with _$Health {
  const factory Health({
    required HealthStatus status,
    required String version,
    required HealthDb db,
  }) = _Health;
  
  factory Health.fromJson(Map<String, Object?> json) => _$HealthFromJson(json);
}
