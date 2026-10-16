// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'book_genre.dart';

part 'book_write.freezed.dart';
part 'book_write.g.dart';

/// A new book, or the complete new state of one.
@Freezed()
abstract class BookWrite with _$BookWrite {
  const factory BookWrite({
    required String title,
    String? author,
    String? description,
    String? isbn,
    BookGenre? genre,
    String? language,
    @JsonKey(name: 'owner_id')
    String? ownerId,
  }) = _BookWrite;
  
  factory BookWrite.fromJson(Map<String, Object?> json) => _$BookWriteFromJson(json);
}
