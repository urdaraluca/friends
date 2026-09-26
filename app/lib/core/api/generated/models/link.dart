// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'link.freezed.dart';
part 'link.g.dart';

@Freezed()
abstract class Link with _$Link {
  const factory Link({
    required String url,
    String? label,
  }) = _Link;
  
  factory Link.fromJson(Map<String, Object?> json) => _$LinkFromJson(json);
}
