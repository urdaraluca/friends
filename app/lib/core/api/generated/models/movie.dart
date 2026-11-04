// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'movie.freezed.dart';
part 'movie.g.dart';

/// What the activity form fills in (contract section 19).
@Freezed()
abstract class Movie with _$Movie {
  const factory Movie({
    @JsonKey(name: 'tmdb_id')
    required int tmdbId,
    required String title,
    @JsonKey(name: 'original_title')
    required String? originalTitle,
    required int? year,
    required String? overview,
    @JsonKey(name: 'poster_url')
    required String? posterUrl,
    @JsonKey(name: 'runtime_min')
    required int? runtimeMin,
    required num? rating,
    required List<String> genres,
    required String? genre,
    @JsonKey(name: 'imdb_url')
    required String? imdbUrl,
  }) = _Movie;
  
  factory Movie.fromJson(Map<String, Object?> json) => _$MovieFromJson(json);
}
