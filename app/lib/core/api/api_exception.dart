import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/api/generated/models/field_error.dart';

export 'package:friends/core/api/generated/models/field_error.dart';

/// Every failed API call surfaces as exactly one of these.
///
/// The main Dio's `ProblemInterceptor` stores the mapped exception in
/// `DioException.error`; [apiCall] unwraps it so callers can write
/// `on ProblemException catch (e)`. Anything else can be mapped with
/// [ApiException.from].
sealed class ApiException implements Exception {
  const new();

  /// Maps any error to an [ApiException]. Already-mapped errors and
  /// [DioException]s carrying one are returned as they are.
  factory from(Object error) => switch (error) {
    final ApiException e => e,
    final DioException e => ApiException.fromDioException(e),
    _ => UnexpectedApiException(cause: error),
  };

  /// Maps a [DioException]: problem+json responses become
  /// [ProblemException], connection problems and timeouts become
  /// [NetworkException], everything else [UnexpectedApiException].
  factory fromDioException(DioException e) {
    if (e.error case final ApiException mapped) return mapped;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return NetworkException(cause: e);
      case DioExceptionType.badResponse:
        final response = e.response;
        return ProblemException.fromResponse(response) ??
            UnexpectedApiException(statusCode: response?.statusCode, cause: e);
      case DioExceptionType.badCertificate:
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
      case DioExceptionType.transformTimeout:
        return UnexpectedApiException(cause: e);
    }
  }
}

/// An RFC 9457 problem+json error response (contract section 1.5).
final class ProblemException extends ApiException {
  const new({
    required this.status,
    required this.code,
    this.detail,
    this.errors = const [],
    this.requestId,
    this.retryAfter,
  });

  /// Parses a problem body, or returns null if [json] isn't one.
  static ProblemException? fromJson(Object? json, {Duration? retryAfter}) {
    if (json is! Map) return null;
    final status = json['status'];
    final code = json['code'];
    if (status is! int || code is! String) return null;
    final errors = <FieldError>[];
    if (json['errors'] case final List<Object?> items) {
      for (final item in items) {
        if (item is! Map) continue;
        final field = item['field'];
        final message = item['message'];
        final type = item['type'];
        if (field is String && message is String) {
          errors.add(
            FieldError(
              field: field,
              message: message,
              type: type is String ? type : '',
            ),
          );
        }
      }
    }
    final detail = json['detail'];
    final requestId = json['request_id'];
    return ProblemException(
      status: status,
      code: code,
      detail: detail is String ? detail : null,
      errors: List.unmodifiable(errors),
      requestId: requestId is String ? requestId : null,
      retryAfter: retryAfter,
    );
  }

  /// Parses an error [response], or returns null if it isn't a problem.
  static ProblemException? fromResponse(Response<Object?>? response) {
    if (response == null) return null;
    var data = response.data;
    if (data is String && data.isNotEmpty) {
      try {
        data = jsonDecode(data);
      } on FormatException {
        return null;
      }
    }
    final retryAfter = int.tryParse(
      response.headers.value('retry-after') ?? '',
    );
    return fromJson(
      data,
      retryAfter: retryAfter == null ? null : Duration(seconds: retryAfter),
    );
  }

  /// HTTP status, e.g. 422.
  final int status;

  /// Stable machine-readable code (see [ErrorCodes]).
  final String code;

  /// English, human-readable; may change. Never parsed.
  final String? detail;

  /// Field errors of a 422 (`field` is a dotted path such as `birthday.day`).
  final List<FieldError> errors;

  /// The server's request ID, for bug reports.
  final String? requestId;

  /// From the `Retry-After` header of a 429.
  final Duration? retryAfter;

  /// A 401 that ends the session: anything but `token_expired`.
  bool get endsSession => status == 401 && code != ErrorCodes.tokenExpired;

  @override
  String toString() =>
      'ProblemException($status $code${detail == null ? '' : ': $detail'})';
}

/// The server couldn't be reached (offline, DNS, timeout, CORS on web).
///
/// Never signs the user out.
final class NetworkException extends ApiException {
  const new({this.cause});

  final Object? cause;

  @override
  String toString() => 'NetworkException($cause)';
}

/// Anything else: a non-problem error response (e.g. an HTML 502 from a
/// proxy), a response that doesn't match the schema, a cancelled request.
final class UnexpectedApiException extends ApiException {
  const new({this.statusCode, this.cause});

  final int? statusCode;
  final Object? cause;

  @override
  String toString() => 'UnexpectedApiException($statusCode, $cause)';
}

/// Runs a generated-client call and rethrows its failure as an
/// [ApiException], keeping the stack trace:
///
/// ```dart
/// final me = await apiCall(ref.read(usersClientProvider).getMe);
/// ```
///
/// A response the generated `fromJson` can't parse (a schema mismatch)
/// becomes an [UnexpectedApiException] with the parse error as its cause.
Future<T> apiCall<T>(Future<T> Function() request) async {
  try {
    return await request();
  } on DioException catch (e, stackTrace) {
    Error.throwWithStackTrace(ApiException.fromDioException(e), stackTrace);
  } on ApiException {
    rethrow;
  } on Object catch (e, stackTrace) {
    Error.throwWithStackTrace(UnexpectedApiException(cause: e), stackTrace);
  }
}

/// The problem `code` of an error [response], or null.
String? problemCodeOf(Response<Object?>? response) =>
    ProblemException.fromResponse(response)?.code;
