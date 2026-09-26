import 'package:friends/core/api/generated/models/me.dart';
import 'package:friends/core/auth/auth_controller.dart';

import 'api_fixtures.dart';

/// An [AuthController] frozen in [initial] (no restore, no network), for
/// router and screen tests. Override with
/// `authControllerProvider.overrideWith(() => FakeAuthController(state))`.
class FakeAuthController extends AuthController {
  new(this.initial);

  final AuthState initial;

  @override
  AuthState build() => initial;

  /// The current state. Setting it moves to another state, as a real
  /// sign-in or sign-out would.
  AuthState get authState => state;

  set authState(AuthState next) => state = next;
}

/// A signed-in state for [meJson].
Authenticated signedIn({String displayName = 'Ana'}) =>
    Authenticated(Me.fromJson(meJson(displayName: displayName)));
