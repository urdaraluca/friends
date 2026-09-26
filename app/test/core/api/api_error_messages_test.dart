import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/api_error_messages.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/error_codes.dart';

void main() {
  ProblemException problem(
    String code, {
    int status = 400,
    List<FieldError> errors = const [],
    Duration? retryAfter,
  }) => ProblemException(
    status: status,
    code: code,
    errors: errors,
    retryAfter: retryAfter,
  );

  group('friendlyErrorMessage', () {
    test('network errors', () {
      final dioError = DioException.connectionError(
        requestOptions: RequestOptions(),
        reason: 'offline',
      );

      expect(
        friendlyErrorMessage(dioError),
        contains("Can't reach the server"),
      );
      expect(isNetworkError(dioError), isTrue);
      expect(isNetworkError(problem(ErrorCodes.notFound)), isFalse);
    });

    test('problem codes', () {
      expect(
        friendlyErrorMessage(problem(ErrorCodes.invalidCredentials)),
        'Wrong email or password.',
      );
      expect(
        friendlyErrorMessage(problem(ErrorCodes.registrationClosed)),
        'Friends is invite-only — ask a friend for an invite link',
      );
      expect(
        friendlyErrorMessage(problem(ErrorCodes.versionConflict)),
        contains('Reload'),
      );
    });

    test('rate limiting mentions Retry-After', () {
      expect(
        friendlyErrorMessage(
          problem(
            ErrorCodes.rateLimited,
            status: 429,
            retryAfter: const Duration(seconds: 30),
          ),
        ),
        'Too many attempts. Try again in 30 seconds.',
      );
      expect(
        friendlyErrorMessage(
          problem(
            ErrorCodes.rateLimited,
            status: 429,
            retryAfter: const Duration(minutes: 10),
          ),
        ),
        'Too many attempts. Try again in 10 minutes.',
      );
    });

    test('a single validation error shows its message', () {
      final error = problem(
        ErrorCodes.validationError,
        status: 422,
        errors: const [
          FieldError(field: 'name', message: 'Too long', type: 'x'),
        ],
      );

      expect(friendlyErrorMessage(error), 'Too long');
    });

    test('screen-specific overrides win', () {
      expect(
        friendlyErrorMessage(
          problem(ErrorCodes.notFound, status: 404),
          messages: const {ErrorCodes.notFound: 'No such invite.'},
        ),
        'No such invite.',
      );
    });

    test('unknown codes and unexpected errors', () {
      expect(
        friendlyErrorMessage(problem('brand_new_code', status: 418)),
        'Something went wrong. Try again.',
      );
      expect(
        friendlyErrorMessage(problem('brand_new_code', status: 503)),
        contains('server is having trouble'),
      );
      expect(
        friendlyErrorMessage(const UnexpectedApiException(statusCode: 502)),
        contains('server is having trouble'),
      );
      expect(
        friendlyErrorMessage(StateError('bug')),
        'Something went wrong. Try again.',
      );
    });
  });
}
