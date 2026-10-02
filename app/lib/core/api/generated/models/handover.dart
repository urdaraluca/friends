// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'handover.freezed.dart';
part 'handover.g.dart';

@Freezed()
abstract class Handover with _$Handover {
  const factory Handover({
    @JsonKey(name: 'to_user_id')
    String? toUserId,
  }) = _Handover;
  
  factory Handover.fromJson(Map<String, Object?> json) => _$HandoverFromJson(json);
}
