import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/forms/field_errors.dart';
import 'package:friends/core/network/dio_provider.dart';
import 'package:friends/core/network/problem_interceptor.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_http_adapter.dart';

void main() {
  late FakeHttpClientAdapter adapter;
  late UsersClient users;

  setUp(() {
    adapter = FakeHttpClientAdapter();
    final dio = Dio(apiBaseOptions('http://api.test'))
      ..httpClientAdapter = adapter
      ..interceptors.add(ProblemInterceptor());
    users = UsersClient(dio);
  });

  Future<ApiException> failure(Future<Object?> Function() call) async {
    try {
      await apiCall(call);
    } on ApiException catch (e) {
      return e;
    }
    fail('Expected an ApiException');
  }

  const update = MeUpdate(displayName: 'Ana', timezone: 'Mars/Olympus');

  group('ProblemInterceptor', () {
    test('422 errors[] map onto form fields', () async {
      adapter.onProblem(
        'PUT',
        ApiPaths.me,
        422,
        ErrorCodes.validationError,
        errors: [
          {
            'field': 'timezone',
            'message': 'unknown IANA timezone',
            'type': 'value_error',
          },
          {
            'field': 'birthday.day',
            'message': 'day is out of range for month',
            'type': 'value_error',
          },
        ],
      );

      final error = await failure(() => users.updateMe(body: update));

      expect(
        error,
        isA<ProblemException>()
            .having((e) => e.status, 'status', 422)
            .having((e) => e.code, 'code', ErrorCodes.validationError)
            .having((e) => e.requestId, 'requestId', 'req-test')
            .having((e) => e.errors, 'errors', hasLength(2)),
      );
      final fields = FieldErrors.fromError(error);
      expect(fields['timezone'], 'unknown IANA timezone');
      expect(fields['birthday'], 'day is out of range for month');
      expect(fields['birthday.day'], 'day is out of range for month');
      expect(fields['display_name'], isNull);
    });

    test('the DioException carries the mapped exception', () async {
      adapter.onProblem('GET', ApiPaths.me, 404, ErrorCodes.notFound);

      try {
        await users.getMe();
        fail('Expected a DioException');
      } on DioException catch (e) {
        expect(e.error, isA<ProblemException>());
        expect(ApiException.from(e), same(e.error));
      }
    });

    test('reads Retry-After on a 429', () async {
      adapter.on(
        'GET',
        ApiPaths.me,
        (_) => FakeReply.problem(
          429,
          ErrorCodes.rateLimited,
          headers: {'retry-after': '42'},
        ),
      );

      final error = await failure(users.getMe);

      expect(
        error,
        isA<ProblemException>().having(
          (e) => e.retryAfter,
          'retryAfter',
          const Duration(seconds: 42),
        ),
      );
    });

    test('a non-problem error response is Unexpected', () async {
      adapter.on(
        'GET',
        ApiPaths.me,
        (_) => const FakeReply.text('<h1>Bad Gateway</h1>', status: 502),
      );

      final error = await failure(users.getMe);

      expect(
        error,
        isA<UnexpectedApiException>().having(
          (e) => e.statusCode,
          'statusCode',
          502,
        ),
      );
    });

    test('a JSON error that is not a problem is Unexpected', () async {
      adapter.onJson('GET', ApiPaths.me, {'detail': 'nope'}, status: 400);

      expect(await failure(users.getMe), isA<UnexpectedApiException>());
    });

    test('a response that does not match the schema is Unexpected', () async {
      adapter.onJson('GET', ApiPaths.me, {'unexpected': true});

      expect(await failure(users.getMe), isA<UnexpectedApiException>());
    });

    test('connection errors and timeouts are Network', () async {
      adapter.on('GET', ApiPaths.me, (_) => const FakeReply.networkError());
      expect(await failure(users.getMe), isA<NetworkException>());

      adapter.on('GET', ApiPaths.me, (_) => const FakeReply.timeout());
      expect(await failure(users.getMe), isA<NetworkException>());
    });
  });

  group('ProblemException.fromJson', () {
    test('ignores malformed entries in errors[]', () {
      final problem = ProblemException.fromJson({
        'status': 422,
        'code': 'validation_error',
        'errors': [
          {'field': 'email', 'message': 'bad', 'type': 'value_error'},
          {'message': 'no field'},
          'garbage',
        ],
      });

      expect(problem!.errors.single.field, 'email');
      expect(problem.detail, isNull);
      expect(problem.requestId, isNull);
    });

    test('returns null for anything that is not a problem', () {
      expect(ProblemException.fromJson(null), isNull);
      expect(ProblemException.fromJson('text'), isNull);
      expect(ProblemException.fromJson({'status': 400}), isNull);
    });
  });

  group('ApiException.from', () {
    test('maps unknown errors to Unexpected', () {
      final error = ApiException.from(StateError('boom'));

      expect(
        error,
        isA<UnexpectedApiException>().having(
          (e) => e.cause,
          'cause',
          isA<StateError>(),
        ),
      );
    });

    test('returns ApiExceptions unchanged', () {
      const network = NetworkException();

      expect(ApiException.from(network), same(network));
    });
  });
}
