import 'package:dio/dio.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/auth/token_holder.dart';
import 'package:friends/core/auth/token_refresher.dart';
import 'package:friends/core/config/env.dart';
import 'package:friends/core/network/auth_interceptor.dart';
import 'package:friends/core/network/problem_interceptor.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dio_provider.g.dart';

/// Origin of the API, without `/api/v1` (the generated paths include it).
///
/// Tests override it, since `Env.apiBaseUrl` needs a `--dart-define`.
@Riverpod(keepAlive: true)
String apiBaseUrl(Ref ref) => Env.apiBaseUrl;

/// Replaces Dio's platform adapter when non-null.
///
/// Tests override this with `FakeHttpClientAdapter` to drive the real network
/// stack (interceptors, refresher, generated clients) without a server.
@Riverpod(keepAlive: true)
HttpClientAdapter? httpClientAdapter(Ref ref) => null;

/// Options shared by both Dio instances (contract section 12).
BaseOptions apiBaseOptions(String baseUrl) => BaseOptions(
  baseUrl: baseUrl,
  connectTimeout: const Duration(seconds: 10),
  receiveTimeout: const Duration(seconds: 20),
  // Repeated keys: ?status=idea&status=planning (wire rule 1).
  listFormat: ListFormat.multi,
);

Dio _newDio(Ref ref) {
  final dio = Dio(apiBaseOptions(ref.watch(apiBaseUrlProvider)));
  final adapter = ref.watch(httpClientAdapterProvider);
  if (adapter != null) dio.httpClientAdapter = adapter;
  ref.onDispose(dio.close);
  return dio;
}

/// A Dio **without** interceptors, for the public endpoints
/// (`publicApiProvider`: health, login, register, refresh, logout, invite
/// preview) and for the auth interceptor's retries. Errors are raw
/// `DioException`s: map them with `apiCall` or
/// `ApiException.fromDioException`.
@Riverpod(keepAlive: true)
Dio bareDio(Ref ref) => _newDio(ref);

/// The main Dio behind every generated client: [AccountStampInterceptor]
/// (which account a request is for), [AuthInterceptor] (tokens, refresh,
/// retry) and then [ProblemInterceptor] (errors to `ApiException`).
@Riverpod(keepAlive: true)
Dio dio(Ref ref) {
  final dio = _newDio(ref);
  // Callbacks, not dependencies: AuthController uses this Dio.
  dio.interceptors.addAll([
    AccountStampInterceptor(
      // No AuthController yet (only in tests): nobody is signed in. Reading
      // currentUserId would create one, and with it a session restore.
      () => ref.exists(authControllerProvider)
          ? ref.read(currentUserIdProvider)
          : null,
    ),
    AuthInterceptor(
      tokens: ref.watch(tokenHolderProvider),
      refresher: ref.watch(tokenRefresherProvider),
      retryDio: ref.watch(bareDioProvider),
      onSessionExpired: () =>
          ref.read(authControllerProvider.notifier).sessionExpired(),
      onAccountChanged: (userId) =>
          ref.read(authControllerProvider.notifier).accountChanged(userId),
    ),
    ProblemInterceptor(),
  ]);
  return dio;
}
