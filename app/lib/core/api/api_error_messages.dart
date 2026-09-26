import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/error_codes.dart';

/// A short, user-facing message for any error thrown by an API call.
///
/// [messages] overrides the text for specific problem codes where the
/// screen knows better, e.g. `{ErrorCodes.notFound: 'No such invite code.'}`.
///
/// ```dart
/// ScaffoldMessenger.of(context).showSnackBar(
///   SnackBar(content: Text(friendlyErrorMessage(error))),
/// );
/// ```
String friendlyErrorMessage(
  Object error, {
  Map<String, String> messages = const {},
}) {
  return switch (ApiException.from(error)) {
    NetworkException() =>
      "Can't reach the server. Check your connection and try again.",
    final ProblemException problem =>
      messages[problem.code] ?? _problemMessage(problem),
    UnexpectedApiException(:final statusCode?) when statusCode >= 500 =>
      'The server is having trouble. Try again in a moment.',
    UnexpectedApiException() => 'Something went wrong. Try again.',
  };
}

/// Whether [error] means the server couldn't be reached.
bool isNetworkError(Object error) =>
    ApiException.from(error) is NetworkException;

String _problemMessage(ProblemException problem) {
  return switch (problem.code) {
    ErrorCodes.validationError =>
      problem.errors.length == 1
          ? problem.errors.single.message
          : 'Please check the highlighted fields.',
    ErrorCodes.unauthenticated ||
    ErrorCodes.refreshInvalid ||
    ErrorCodes.refreshReuseDetected ||
    ErrorCodes.tokenExpired => 'Your session has ended. Please sign in again.',
    ErrorCodes.invalidCredentials => 'Wrong email or password.',
    ErrorCodes.wrongPassword => 'Wrong password.',
    ErrorCodes.weakPassword => "Your password can't be your email address.",
    ErrorCodes.forbidden => "You don't have permission to do that.",
    ErrorCodes.registrationClosed =>
      'Friends is invite-only — ask a friend for an invite link',
    ErrorCodes.notFound => "That doesn't exist anymore, or you can't see it.",
    ErrorCodes.emailTaken => 'An account with this email already exists.',
    ErrorCodes.nameTaken => 'That name is already taken.',
    ErrorCodes.versionConflict =>
      'Someone else changed this in the meantime. Reload to see their '
          'changes.',
    ErrorCodes.ownerMustTransfer =>
      'Transfer ownership of the group to someone else first.',
    ErrorCodes.pollClosed => 'This poll is closed.',
    ErrorCodes.resultDeleted => 'That activity has been deleted.',
    ErrorCodes.inviteExpired => 'This invite has expired.',
    ErrorCodes.inviteRevoked => 'This invite has been revoked.',
    ErrorCodes.inviteExhausted => 'This invite has already been used up.',
    ErrorCodes.limitReached => "You've reached the limit for this.",
    ErrorCodes.rangeTooLarge => 'Pick a shorter date range.',
    ErrorCodes.notEnoughCandidates =>
      'The wheel needs at least two activities.',
    ErrorCodes.rateLimited => _rateLimitedMessage(problem.retryAfter),
    ErrorCodes.internalError =>
      'The server is having trouble. Try again in a moment.',
    _ =>
      problem.status >= 500
          ? 'The server is having trouble. Try again in a moment.'
          : 'Something went wrong. Try again.',
  };
}

String _rateLimitedMessage(Duration? retryAfter) {
  if (retryAfter == null) return 'Too many attempts. Try again in a moment.';
  final seconds = retryAfter.inSeconds;
  if (seconds < 90) {
    return 'Too many attempts. Try again in $seconds seconds.';
  }
  final minutes = (seconds / 60).ceil();
  return 'Too many attempts. Try again in $minutes minutes.';
}
