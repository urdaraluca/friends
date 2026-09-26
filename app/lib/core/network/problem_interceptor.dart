import 'package:dio/dio.dart';
import 'package:friends/core/api/api_exception.dart';

/// Maps every failed request of the main Dio to an [ApiException], stored in
/// `DioException.error`. problem+json bodies (contract section 1.5) become
/// [ProblemException]s.
///
/// Dio always throws a [DioException]; use `apiCall` (or
/// `ApiException.from`) to get at the mapped exception.
class ProblemInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.error is ApiException) return handler.next(err);
    handler.next(err.copyWith(error: ApiException.fromDioException(err)));
  }
}
