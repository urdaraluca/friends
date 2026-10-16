// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'rating_write.freezed.dart';
part 'rating_write.g.dart';

@Freezed()
abstract class RatingWrite with _$RatingWrite {
  const factory RatingWrite({
    required int stars,
  }) = _RatingWrite;
  
  factory RatingWrite.fromJson(Map<String, Object?> json) => _$RatingWriteFromJson(json);
}
