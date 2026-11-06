// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'book_search_result.freezed.dart';
part 'book_search_result.g.dart';

/// A book matching a search by title or author (contract section 17.5).
@Freezed()
abstract class BookSearchResult with _$BookSearchResult {
  const factory BookSearchResult({
    required String title,
    required String? author,
    required int? year,
    required String? isbn,
    required String? language,
    @JsonKey(name: 'cover_url')
    required String? coverUrl,
  }) = _BookSearchResult;
  
  factory BookSearchResult.fromJson(Map<String, Object?> json) => _$BookSearchResultFromJson(json);
}
