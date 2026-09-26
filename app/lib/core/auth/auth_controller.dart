import 'dart:async';

import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/api_providers.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_state.dart';
import 'package:friends/core/auth/token_refresher.dart';
import 'package:friends/core/auth/token_store.dart';
import 'package:friends/core/device/device_info.dart';
import 'package:friends/core/invites/invite_code.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

export 'package:friends/core/auth/auth_state.dart';

part 'auth_controller.g.dart';

/// The session: restores it on startup, signs in and out, and edits the
/// signed-in user (contract sections 4 and 8.2–8.3).
///
/// Every method throws `ApiException`s; screens map them with
/// `friendlyErrorMessage` and `FieldErrors`.
@Riverpod(keepAlive: true)
class AuthController extends _$AuthController {
  Future<void>? _restoring;

  @override
  AuthState build() {
    unawaited(Future.microtask(restore));
    return const AuthUnknown();
  }

  TokenRefresher get _tokens => ref.read(tokenRefresherProvider);

  /// Restores the stored session: refresh, then `GET /me`.
  ///
  /// No stored session, or a 401: [Unauthenticated]. A network failure, 429
  /// or 5xx keeps the stored session and leaves [AuthUnknown] with the
  /// error, so the splash screen can offer Retry.
  Future<void> restore() =>
      _restoring ??= _restore().whenComplete(() => _restoring = null);

  Future<void> _restore() async {
    if (!ref.mounted || state is Authenticated) return;
    state = const AuthUnknown();
    try {
      final stored = await ref.read(tokenStoreProvider).readRefreshToken();
      if (!ref.mounted) return;
      if (stored == null) {
        state = const Unauthenticated(SignOutReason.noSession);
        return;
      }
      await _tokens.refresh();
      final me = await apiCall(ref.read(usersClientProvider).getMe);
      if (ref.mounted) state = Authenticated(me);
    } on ProblemException catch (e) {
      if (!ref.mounted) return;
      if (e.status == 401) {
        await _tokens.clear(onlyIfOwn: true);
        state = const Unauthenticated(SignOutReason.sessionExpired);
      } else {
        state = AuthUnknown(error: e);
      }
    } on Object catch (e) {
      // Network errors, 5xx, and anything unexpected (e.g. storage errors).
      if (ref.mounted) state = AuthUnknown(error: ApiException.from(e));
    }
  }

  /// `POST /auth/login`. Returns the session (its `joinedGroup` is null).
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final session = await apiCall(
      () => ref
          .read(publicAuthClientProvider)
          .login(
            body: LoginRequest(
              email: email.trim(),
              password: password,
              deviceLabel: ref.read(deviceLabelProvider),
            ),
          ),
    );
    await _startSession(session);
    return session;
  }

  /// `POST /auth/register` with this device's label and IANA timezone.
  ///
  /// [inviteCode] may be in any spelling or a pasted `…/join/<code>` link;
  /// it is normalized as in contract section 4.7. When the invite put the
  /// user in a group, the returned session's `joinedGroup` names it, and
  /// the register screen opens that group.
  Future<AuthSession> register({
    required String displayName,
    required String email,
    required String password,
    String? inviteCode,
  }) async {
    final code = inviteCode?.trim() ?? '';
    final timezone = await ref.read(deviceTimezoneProvider.future);
    final session = await apiCall(
      () => ref
          .read(publicAuthClientProvider)
          .register(
            body: RegisterRequest(
              email: email.trim(),
              password: password,
              displayName: displayName.trim(),
              timezone: timezone,
              deviceLabel: ref.read(deviceLabelProvider),
              inviteCode: code.isEmpty
                  ? null
                  : InviteCode.parse(code) ?? InviteCode.normalize(code),
            ),
          ),
    );
    await _startSession(session);
    return session;
  }

  Future<void> _startSession(AuthSession session) async {
    await _tokens.save(session.tokens);
    state = Authenticated(session.user);
  }

  /// Logs out this device, **locally first**: clears the tokens and signs
  /// out at once, then sends a best-effort `POST /auth/logout` (public, on
  /// the bare Dio) so the server revokes the session. Offline or on a slow
  /// network the user is still signed out immediately; the returned future
  /// completes once the server call has finished or failed.
  Future<void> logout() async {
    final refreshToken = await ref.read(tokenStoreProvider).readRefreshToken();
    await _signOut(SignOutReason.signedOut);
    if (refreshToken == null) return;
    try {
      await apiCall(
        () => ref
            .read(publicAuthClientProvider)
            .logout(body: RefreshRequest(refreshToken: refreshToken)),
      );
    } on ApiException {
      // Best effort: the session is already dropped locally.
    }
  }

  /// `POST /auth/logout-all`: ends every session, including this one.
  /// Throws (and stays signed in) when the server can't be reached.
  Future<void> logoutAll() async {
    await apiCall(ref.read(authClientProvider).logoutAll);
    await _signOut(SignOutReason.signedOut);
  }

  /// The server ended the session (any 401 other than `token_expired`).
  /// Called by the network layer; does nothing when already signed out.
  ///
  /// The stored refresh token is kept when another tab has stored a newer
  /// session meanwhile (`TokenRefresher.clear(onlyIfOwn: true)`).
  void sessionExpired() {
    if (!ref.mounted || state is Unauthenticated) return;
    unawaited(_tokens.clear(onlyIfOwn: true));
    state = const Unauthenticated(SignOutReason.sessionExpired);
  }

  /// The access token now belongs to the account [userId], not to the
  /// signed-in user. On web, another tab signed in as someone else and this
  /// tab picked that session up from the shared storage on a refresh.
  ///
  /// Called by the network layer, which refuses to send the previous
  /// account's requests with that token. Goes back to [AuthUnknown] (the
  /// router shows the splash screen, so no screen keeps the previous user's
  /// data) and restores the session, which loads the new user: the
  /// `currentUserId` changes and every cache resets.
  void accountChanged(String userId) {
    if (!ref.mounted) return;
    if (state case Authenticated(:final user) when user.id != userId) {
      state = const AuthUnknown();
      unawaited(restore());
    }
  }

  /// `PUT /me`. [update] is the complete new profile (PUT semantics), so
  /// copy `locale` and `avatarUrl` from the current user when not editing
  /// them.
  Future<Me> updateMe(MeUpdate update) async {
    final me = await apiCall(
      () => ref.read(usersClientProvider).updateMe(body: update),
    );
    if (ref.mounted && state is Authenticated) state = Authenticated(me);
    return me;
  }

  /// `POST /me/password`. Every other session ends; this one continues with
  /// the returned token pair. A wrong current password is a 422
  /// `wrong_password` on `current_password`.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final tokens = await apiCall(
      () => ref
          .read(usersClientProvider)
          .changePassword(
            body: PasswordChange(
              currentPassword: currentPassword,
              newPassword: newPassword,
            ),
          ),
    );
    await _tokens.save(tokens);
  }

  /// `POST /me/deletion`: deletes the account after a password check, then
  /// signs out.
  Future<void> deleteAccount({required String password}) async {
    await apiCall(
      () => ref
          .read(usersClientProvider)
          .deleteAccount(body: AccountDeletion(password: password)),
    );
    await _signOut(SignOutReason.accountDeleted);
  }

  Future<void> _signOut(SignOutReason reason) async {
    await _tokens.clear();
    if (ref.mounted) state = Unauthenticated(reason);
  }
}

/// The signed-in user, or null.
@Riverpod(keepAlive: true)
Me? currentUser(Ref ref) => switch (ref.watch(authControllerProvider)) {
  Authenticated(:final user) => user,
  _ => null,
};

/// The signed-in user's ID, or null.
///
/// **Every data provider watches this**, so cached data is thrown away on
/// logout and when another account signs in:
///
/// ```dart
/// @riverpod
/// Future<List<GroupSummary>> groups(Ref ref) {
///   ref.watch(currentUserIdProvider);
///   return apiCall(ref.watch(groupsClientProvider).listGroups);
/// }
/// ```
@Riverpod(keepAlive: true)
String? currentUserId(Ref ref) => ref.watch(currentUserProvider)?.id;
