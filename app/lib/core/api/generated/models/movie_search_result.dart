// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'movie_search_result.freezed.dart';
part 'movie_search_result.g.dart';

@Freezed()
abstract class MovieSearchResult with _$MovieSearchResult {
  const factory MovieSearchResult({
    @JsonKey(name: 'tmdb_id')
    required int tmdbId,
    required String title,
    @JsonKey(name: 'original_title')
    required String? originalTitle,
    required int? year,
    required String? overview,
    @JsonKey(name: 'poster_url')
    required String? posterUrl,
  }) = _MovieSearchResult;
  
  factory MovieSearchResult.fromJson(Map<String, Object?> json) => _$MovieSearchResultFromJson(json);
}
