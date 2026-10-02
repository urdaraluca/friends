// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'book_write.freezed.dart';
part 'book_write.g.dart';

/// A new book (the caller owns it), or the complete new state of one.
@Freezed()
abstract class BookWrite with _$BookWrite {
  const factory BookWrite({
    required String title,
    String? author,
    String? description,
  }) = _BookWrite;
  
  factory BookWrite.fromJson(Map<String, Object?> json) => _$BookWriteFromJson(json);
}
