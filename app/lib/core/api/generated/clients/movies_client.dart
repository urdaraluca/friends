// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/movie.dart';
import '../models/movie_search_result.dart';

part 'movies_client.g.dart';

@RestApi()
abstract class MoviesClient {
  factory MoviesClient(Dio dio, {String? baseUrl}) = _MoviesClient;

  /// Search Movies.
  ///
  /// Up to 10 TMDB matches, in my language when TMDB has it. 503 ``lookup_unavailable``.
  /// when the server has no TMDB key or TMDB can't be reached.
  @GET('/api/v1/movies/search')
  Future<List<MovieSearchResult>> searchMovies({
    @Query('query') required String query,
    @Query('year') int? year,
  });

  /// Get Movie.
  ///
  /// One movie's details for the activity form.
  @GET('/api/v1/movies/{tmdb_id}')
  Future<Movie> getMovie({
    @Path('tmdb_id') required int tmdbId,
  });
}
