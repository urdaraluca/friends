// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'wheel_spin.dart';

part 'wheel_spin_page.freezed.dart';
part 'wheel_spin_page.g.dart';

@Freezed()
abstract class WheelSpinPage with _$WheelSpinPage {
  const factory WheelSpinPage({
    required List<WheelSpin> items,
    @JsonKey(name: 'next_cursor')
    required String? nextCursor,
  }) = _WheelSpinPage;
  
  factory WheelSpinPage.fromJson(Map<String, Object?> json) => _$WheelSpinPageFromJson(json);
}
