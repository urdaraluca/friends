import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Answers a [RecordedRequest].
typedef FakeHandler = FutureOr<FakeReply> Function(RecordedRequest request);

/// A scripted [HttpClientAdapter]: tests register replies per method and
/// path, then assert on [requests] (query strings, headers, JSON bodies).
///
/// ```dart
/// final adapter = FakeHttpClientAdapter()
///   ..onJson('GET', '/api/v1/me', meJson())
///   ..onProblem('POST', '/api/v1/auth/login', 401, 'invalid_credentials');
/// dio.httpClientAdapter = adapter; // or override httpClientAdapterProvider
/// ...
/// expect(adapter.last.query, 'status=idea&status=planning');
/// ```
///
/// Unmatched requests get a problem+json 404, so a missing stub fails loudly.
class FakeHttpClientAdapter implements HttpClientAdapter {
  final List<RecordedRequest> requests = [];
  final List<_Route> _routes = [];

  /// The most recent request.
  RecordedRequest get last => requests.last;

  /// Answers [method] requests whose path matches [path] with [handler].
  /// A [String] path must match exactly; a [RegExp] must match the whole
  /// path. Later registrations win.
  void on(String method, Pattern path, FakeHandler handler) =>
      _routes.insert(0, _Route(method.toUpperCase(), path, handler));

  /// Answers with a JSON body.
  void onJson(String method, Pattern path, Object? body, {int status = 200}) =>
      on(method, path, (_) => FakeReply.json(body, status: status));

  /// Answers with a problem+json error.
  void onProblem(
    String method,
    Pattern path,
    int status,
    String code, {
    List<Map<String, String>> errors = const [],
  }) =>
      on(method, path, (_) => FakeReply.problem(status, code, errors: errors));

  /// Requests sent to [method] [path] (exact path).
  List<RecordedRequest> requestsTo(String method, String path) => [
    for (final request in requests)
      if (request.method == method.toUpperCase() && request.path == path)
        request,
  ];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    String? body;
    if (requestStream != null) {
      final bytes = <int>[];
      await requestStream.forEach(bytes.addAll);
      body = utf8.decode(bytes);
    }
    final request = RecordedRequest(options, body);
    requests.add(request);
    final route = _routes.where((r) => r.matches(request)).firstOrNull;
    final reply = route == null
        ? FakeReply.problem(404, 'not_found')
        : await route.handler(request);
    return reply._toResponseBody(options);
  }

  @override
  void close({bool force = false}) {}
}

class _Route {
  new(this.method, this.path, this.handler);

  final String method;
  final Pattern path;
  final FakeHandler handler;

  bool matches(RecordedRequest request) {
    if (request.method != method) return false;
    final path = this.path;
    if (path is String) return request.path == path;
    final match = path.matchAsPrefix(request.path);
    return match != null && match.end == request.path.length;
  }
}

/// A request as the server would see it.
class RecordedRequest {
  new(this.options, this.body);

  final RequestOptions options;

  /// The raw request body, or null.
  final String? body;

  String get method => options.method.toUpperCase();

  Uri get uri => options.uri;

  String get path => uri.path;

  /// The encoded query string, exactly as sent (`status=idea&status=...`).
  String get query => uri.query;

  /// Every value of each query parameter.
  Map<String, List<String>> get queryParametersAll => uri.queryParametersAll;

  /// The `Authorization` header, or null.
  String? get authorization => options.headers['Authorization'] as String?;

  /// The body decoded as JSON.
  Object? get json => body == null ? null : jsonDecode(body!);

  /// The body decoded as a JSON object.
  Map<String, Object?> get jsonMap => json! as Map<String, Object?>;

  @override
  String toString() => '$method $uri';
}

/// What the fake server answers.
class FakeReply {
  /// A JSON response.
  new json(Object? body, {this.status = 200})
    : _body = jsonEncode(body),
      _contentType = 'application/json',
      _error = null,
      headers = const {};

  /// A problem+json response (contract section 1.5).
  new problem(
    this.status,
    String code, {
    String? detail,
    List<Map<String, String>> errors = const [],
    this.headers = const {},
  }) : _body = jsonEncode({
         'type': 'about:blank',
         'title': 'Error',
         'status': status,
         'detail': detail,
         'code': code,
         'errors': errors.isEmpty ? null : errors,
         'request_id': 'req-test',
       }),
       _contentType = 'application/problem+json',
       _error = null;

  /// A 204 without a body.
  const new noContent()
    : status = 204,
      _body = '',
      _contentType = null,
      _error = null,
      headers = const {};

  /// A plain-text (non-problem) response, e.g. a proxy's error page.
  const new text(
    String body, {
    this.status = 200,
    String this._contentType = 'text/html',
  }) : _body = body,
       _error = null,
       headers = const {};

  /// The connection fails, as when offline.
  const new networkError()
    : status = 0,
      _body = '',
      _contentType = null,
      _error = DioExceptionType.connectionError,
      headers = const {};

  /// The connection times out.
  const new timeout()
    : status = 0,
      _body = '',
      _contentType = null,
      _error = DioExceptionType.connectionTimeout,
      headers = const {};

  final int status;
  final Map<String, String> headers;
  final String _body;
  final String? _contentType;
  final DioExceptionType? _error;

  ResponseBody _toResponseBody(RequestOptions options) {
    if (_error == DioExceptionType.connectionTimeout) {
      throw DioException.connectionTimeout(
        requestOptions: options,
        timeout: const Duration(seconds: 10),
      );
    }
    if (_error != null) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'Fake network error',
      );
    }
    return ResponseBody.fromString(
      _body,
      status,
      headers: {
        if (_contentType != null) Headers.contentTypeHeader: [_contentType],
        for (final MapEntry(:key, :value) in headers.entries) key: [value],
      },
    );
  }
}
