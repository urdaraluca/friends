// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'birthday_public.freezed.dart';
part 'birthday_public.g.dart';

@Freezed()
abstract class BirthdayPublic with _$BirthdayPublic {
  const factory BirthdayPublic({
    required int month,
    required int day,
  }) = _BirthdayPublic;
  
  factory BirthdayPublic.fromJson(Map<String, Object?> json) => _$BirthdayPublicFromJson(json);
}
