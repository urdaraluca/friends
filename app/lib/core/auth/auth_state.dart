import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/generated/models/me.dart';
import 'package:material_ui/material_ui.dart' show immutable;

/// Where the session stands. The router redirects on it.
@immutable
sealed class AuthState {
  const new();
}

/// Restoring the session on startup, or restoring failed without ending it.
///
/// [error] is null while restoring. After a network failure (or a 429/5xx)
/// it holds the error, the stored session is kept, and the splash screen
/// offers Retry.
final class AuthUnknown extends AuthState {
  const new({this.error});

  final ApiException? error;

  @override
  bool operator ==(Object other) =>
      other is AuthUnknown && identical(other.error, error);

  @override
  int get hashCode => Object.hash(AuthUnknown, error);
}

/// Signed out.
final class Unauthenticated extends AuthState {
  const new(this.reason);

  final SignOutReason reason;

  @override
  bool operator ==(Object other) =>
      other is Unauthenticated && other.reason == reason;

  @override
  int get hashCode => Object.hash(Unauthenticated, reason);
}

/// Why the user is signed out; the login screen explains the last two.
enum SignOutReason {
  /// No stored session on startup.
  noSession,

  /// The user logged out (here or everywhere).
  signedOut,

  /// The server ended the session (refresh token revoked, logout-all or a
  /// password change elsewhere).
  sessionExpired,

  /// The user deleted their account.
  accountDeleted,
}

/// Signed in as [user].
final class Authenticated extends AuthState {
  const new(this.user);

  final Me user;

  @override
  bool operator ==(Object other) =>
      other is Authenticated && other.user == user;

  @override
  int get hashCode => Object.hash(Authenticated, user);
}
