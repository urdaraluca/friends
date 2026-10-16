// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'book_genre.dart';

part 'book_create.freezed.dart';
part 'book_create.g.dart';

@Freezed()
abstract class BookCreate with _$BookCreate {
  const factory BookCreate({
    required String title,
    String? author,
    String? description,
    String? isbn,
    BookGenre? genre,
    String? language,
    @JsonKey(name: 'owner_id')
    String? ownerId,
    @JsonKey(name: 'holder_id')
    String? holderId,
  }) = _BookCreate;
  
  factory BookCreate.fromJson(Map<String, Object?> json) => _$BookCreateFromJson(json);
}
