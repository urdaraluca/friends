// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'birthday.freezed.dart';
part 'birthday.g.dart';

@Freezed()
abstract class Birthday with _$Birthday {
  const factory Birthday({
    required int month,
    required int day,
    int? year,
  }) = _Birthday;
  
  factory Birthday.fromJson(Map<String, Object?> json) => _$BirthdayFromJson(json);
}
