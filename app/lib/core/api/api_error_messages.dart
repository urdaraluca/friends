import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/l10n/l10n.dart';

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
  final l10n = currentL10n;
  return switch (ApiException.from(error)) {
    NetworkException() => l10n.errorNetwork,
    final ProblemException problem =>
      messages[problem.code] ?? _problemMessage(problem),
    UnexpectedApiException(:final statusCode?) when statusCode >= 500 =>
      l10n.errorServer,
    UnexpectedApiException() => l10n.errorGeneric,
  };
}

/// Whether [error] means the server couldn't be reached.
bool isNetworkError(Object error) =>
    ApiException.from(error) is NetworkException;

String _problemMessage(ProblemException problem) {
  final l10n = currentL10n;
  return switch (problem.code) {
    ErrorCodes.validationError =>
      problem.errors.length == 1
          ? problem.errors.single.message
          : l10n.errorCheckFields,
    ErrorCodes.unauthenticated ||
    ErrorCodes.refreshInvalid ||
    ErrorCodes.refreshReuseDetected ||
    ErrorCodes.tokenExpired => l10n.errorSessionEnded,
    ErrorCodes.invalidCredentials => l10n.errorInvalidCredentials,
    ErrorCodes.wrongPassword => l10n.errorWrongPassword,
    ErrorCodes.weakPassword => l10n.errorWeakPassword,
    ErrorCodes.forbidden => l10n.errorForbidden,
    ErrorCodes.registrationClosed => l10n.errorRegistrationClosed,
    ErrorCodes.notFound => l10n.errorNotFound,
    ErrorCodes.emailTaken => l10n.errorEmailTaken,
    ErrorCodes.nameTaken => l10n.errorNameTaken,
    ErrorCodes.versionConflict => l10n.errorVersionConflict,
    ErrorCodes.ownerMustTransfer => l10n.errorOwnerMustTransfer,
    ErrorCodes.pollClosed => l10n.errorPollClosed,
    ErrorCodes.ownBook => l10n.ownBookError,
    ErrorCodes.alreadyHolding => l10n.alreadyHoldingError,
    ErrorCodes.resultDeleted => l10n.errorResultDeleted,
    ErrorCodes.inviteExpired => l10n.errorInviteExpired,
    ErrorCodes.inviteRevoked => l10n.errorInviteRevoked,
    ErrorCodes.inviteExhausted => l10n.errorInviteExhausted,
    ErrorCodes.limitReached => l10n.errorLimitReached,
    ErrorCodes.rangeTooLarge => l10n.errorRangeTooLarge,
    ErrorCodes.notEnoughCandidates => l10n.errorNotEnoughCandidates,
    ErrorCodes.rateLimited => _rateLimitedMessage(problem.retryAfter),
    ErrorCodes.internalError => l10n.errorServer,
    _ => problem.status >= 500 ? l10n.errorServer : l10n.errorGeneric,
  };
}

String _rateLimitedMessage(Duration? retryAfter) {
  final l10n = currentL10n;
  if (retryAfter == null) return l10n.errorRateLimited;
  final seconds = retryAfter.inSeconds;
  if (seconds < 90) return l10n.errorRateLimitedSeconds(seconds);
  return l10n.errorRateLimitedMinutes((seconds / 60).ceil());
}
