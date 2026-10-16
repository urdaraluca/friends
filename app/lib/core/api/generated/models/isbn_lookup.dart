// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'book_genre.dart';

part 'isbn_lookup.freezed.dart';
part 'isbn_lookup.g.dart';

/// What the book catalogues know about an ISBN; the app fills its form with it.
@Freezed()
abstract class IsbnLookup with _$IsbnLookup {
  const factory IsbnLookup({
    required String isbn,
    required String title,
    required String? author,
    required String? description,
    required BookGenre? genre,
    required String? language,
    @JsonKey(name: 'cover_url')
    required String? coverUrl,
  }) = _IsbnLookup;
  
  factory IsbnLookup.fromJson(Map<String, Object?> json) => _$IsbnLookupFromJson(json);
}
