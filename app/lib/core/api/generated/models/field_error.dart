// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'field_error.freezed.dart';
part 'field_error.g.dart';

@Freezed()
abstract class FieldError with _$FieldError {
  const factory FieldError({
    required String field,
    required String message,
    required String type,
  }) = _FieldError;
  
  factory FieldError.fromJson(Map<String, Object?> json) => _$FieldErrorFromJson(json);
}
