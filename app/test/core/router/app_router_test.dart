import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/router/app_router.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/features/auth/presentation/login_screen.dart';
import 'package:friends/features/auth/presentation/register_screen.dart';
import 'package:friends/features/home/presentation/home_screen.dart';
import 'package:friends/features/invites/presentation/join_screen.dart';
import 'package:friends/features/profile/presentation/profile_screen.dart';

import '../../helpers/fake_auth_controller.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/test_backend.dart';

void main() {
  const unknown = AuthUnknown();
  const signedOut = Unauthenticated(SignOutReason.noSession);
  final signedInState = signedIn();

  String? redirect(AuthState auth, String location) =>
      authRedirect(auth, Uri.parse(location));

  group('authRedirect', () {
    test('signed out: /profile goes to /login?from=%2Fprofile', () {
      expect(redirect(signedOut, '/profile'), '/login?from=%2Fprofile');
      expect(redirect(signedOut, '/'), '/login');
    });

    test('an expired session returns to where the user was', () {
      const expired = Unauthenticated(SignOutReason.sessionExpired);

      expect(redirect(expired, '/profile'), '/login?from=%2Fprofile');
    });

    test('an explicit sign-out or deletion goes to plain /login', () {
      const loggedOut = Unauthenticated(SignOutReason.signedOut);
      const deleted = Unauthenticated(SignOutReason.accountDeleted);

      expect(redirect(loggedOut, '/profile'), '/login');
      expect(redirect(deleted, '/profile'), '/login');
      expect(redirect(loggedOut, '/join/X'), isNull);
    });

    test('signed out: public routes stay', () {
      expect(redirect(signedOut, '/join/ABCDE-FGHJK'), isNull);
      expect(redirect(signedOut, '/login'), isNull);
      expect(redirect(signedOut, '/login?from=%2Fprofile'), isNull);
      expect(redirect(signedOut, '/register?invite=X'), isNull);
      expect(redirect(signedOut, '/health'), isNull);
    });

    test('signed out on the splash screen: back to a public from, else '
        'login', () {
      expect(redirect(signedOut, '/splash?from=%2Fjoin%2FX'), '/join/X');
      expect(
        redirect(signedOut, '/splash?from=%2Fprofile'),
        '/login?from=%2Fprofile',
      );
      expect(redirect(signedOut, '/splash'), '/login');
    });

    test('signed in: auth screens go to from, or /', () {
      expect(redirect(signedInState, '/login'), '/');
      expect(redirect(signedInState, '/register'), '/');
      expect(redirect(signedInState, '/splash'), '/');
      expect(redirect(signedInState, '/login?from=%2Fprofile'), '/profile');
      expect(redirect(signedInState, '/splash?from=%2Fjoin%2FX'), '/join/X');
    });

    test('signed in: other routes stay', () {
      expect(redirect(signedInState, '/'), isNull);
      expect(redirect(signedInState, '/profile'), isNull);
      expect(redirect(signedInState, '/join/X'), isNull);
      expect(redirect(signedInState, '/health'), isNull);
    });

    test('unknown: everything waits on the splash screen', () {
      expect(redirect(unknown, '/'), '/splash');
      expect(redirect(unknown, '/profile'), '/splash?from=%2Fprofile');
      expect(redirect(unknown, '/join/X'), '/splash?from=%2Fjoin%2FX');
      expect(redirect(unknown, '/splash?from=%2Fprofile'), isNull);
      expect(redirect(unknown, '/health'), isNull);
    });

    test('unknown: the auth screens keep their whole location', () {
      expect(redirect(unknown, '/login'), '/splash?from=%2Flogin');
      expect(
        redirect(unknown, '/register?invite=ABCDEFGHJK'),
        '/splash?from=%2Fregister%3Finvite%3DABCDEFGHJK',
      );
      expect(
        redirect(unknown, '/login?from=%2Fprofile'),
        '/splash?from=%2Flogin%3Ffrom%3D%252Fprofile',
      );
    });

    group('a cold start (page load or reload) on an auth screen', () {
      /// Follows redirects, as go_router does, from [location]: first while
      /// the session is restored, then in [restored].
      String land(String location, AuthState restored) {
        var current = location;
        for (final auth in [unknown, restored]) {
          for (var hops = 0; hops < 5; hops++) {
            final next = redirect(auth, current);
            if (next == null) break;
            current = next;
          }
        }
        return current;
      }

      test('signed out: /register keeps its invite code', () {
        expect(
          land('/register?invite=ABCDEFGHJK', signedOut),
          '/register?invite=ABCDEFGHJK',
        );
        expect(land('/register', signedOut), '/register');
      });

      test('signed out: /login keeps its from', () {
        expect(
          land('/login?from=%2Fprofile', signedOut),
          '/login?from=%2Fprofile',
        );
        expect(land('/login', signedOut), '/login');
      });

      test('signed in: the nested from is the destination', () {
        expect(land('/login?from=%2Fprofile', signedInState), '/profile');
        expect(land('/login?from=%2Fjoin%2FX', signedInState), '/join/X');
        expect(land('/register?invite=ABCDEFGHJK', signedInState), '/');
        expect(land('/login', signedInState), '/');
      });

      test('other pages are unchanged', () {
        expect(land('/profile', signedOut), '/login?from=%2Fprofile');
        expect(land('/profile', signedInState), '/profile');
        expect(land('/join/X', signedOut), '/join/X');
      });
    });

    test('signed in on the splash screen with an auth screen as from', () {
      expect(
        redirect(
          signedInState,
          Routes.splashWith(from: '/login?from=%2Fprofile'),
        ),
        '/profile',
      );
      expect(
        redirect(signedInState, Routes.splashWith(from: '/register?invite=X')),
        '/',
      );
    });

    test('from never leaves the app or loops back to an auth screen', () {
      expect(redirect(signedInState, '/login?from=https://evil.test'), '/');
      expect(redirect(signedInState, '/login?from=//evil.test/x'), '/');
      expect(redirect(signedInState, '/login?from=%2Flogin'), '/');
      expect(
        redirect(
          signedInState,
          '/splash?from=${Uri.encodeComponent('/login?from=https://evil.test')}',
        ),
        '/',
      );
      expect(redirect(signedOut, '/splash?from=//evil.test'), '/login');
      expect(redirect(signedOut, '/splash?from=%2Fsplash'), '/login');
    });
  });

  group('Routes', () {
    test('path builders', () {
      expect(Routes.join('ABCDEFGHJK'), '/join/ABCDEFGHJK');
      expect(Routes.loginWith(from: '/profile'), '/login?from=%2Fprofile');
      expect(Routes.loginWith(from: '/'), '/login');
      expect(Routes.loginWith(), '/login');
      expect(Routes.splashWith(from: '/login'), '/splash?from=%2Flogin');
      expect(Routes.splashWith(from: '/'), '/splash');
      expect(Routes.splashWith(from: '/splash?from=%2Fprofile'), '/splash');
      expect(Routes.splashWith(from: 'https://evil.test'), '/splash');
      expect(Routes.loginWith(from: '/register'), '/login');
      expect(Routes.afterSignIn('/login?from=%2Fprofile'), '/profile');
      expect(Routes.afterSignIn(null), '/');
      expect(
        Routes.registerWith(invite: 'ABCDEFGHJK'),
        '/register?invite=ABCDEFGHJK',
      );
    });
  });

  group('routerProvider', () {
    testWidgets('signed out, /profile shows the login screen', (tester) async {
      final container = await tester.pumpFriendsApp(
        overrides: [
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedOut),
          ),
        ],
        location: Routes.profile,
      );

      expect(currentLocation(container), '/login?from=%2Fprofile');
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('/join/:code stays public', (tester) async {
      final container = await tester.pumpFriendsApp(
        overrides: [
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedOut),
          ),
        ],
        location: '/join/ABCDE-FGHJK',
      );

      expect(currentLocation(container), '/join/ABCDE-FGHJK');
      expect(find.byType(JoinScreen), findsOneWidget);
      expect(find.text('ABCDE-FGHJK'), findsOneWidget);
    });

    testWidgets('signed in, /login goes home', (tester) async {
      final container = await tester.pumpFriendsApp(
        overrides: [
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedInState),
          ),
        ],
        location: Routes.login,
      );

      expect(currentLocation(container), '/');
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('Hi, Ana!'), findsOneWidget);
    });

    testWidgets('follows auth state changes (refreshListenable)', (
      tester,
    ) async {
      final auth = FakeAuthController(unknown);
      final container = await tester.pumpFriendsApp(
        overrides: [authControllerProvider.overrideWith(() => auth)],
        location: Routes.profile,
        settle: false,
      );
      expect(currentLocation(container), '/splash?from=%2Fprofile');

      auth.authState = signedOut;
      await tester.pumpAndSettle();
      expect(currentLocation(container), '/login?from=%2Fprofile');

      auth.authState = signedInState;
      await tester.pumpAndSettle();
      expect(currentLocation(container), '/profile');
      expect(find.byType(ProfileScreen), findsOneWidget);

      auth.authState = const Unauthenticated(SignOutReason.sessionExpired);
      await tester.pumpAndSettle();
      expect(currentLocation(container), '/login?from=%2Fprofile');
      expect(
        find.text('Your session has ended. Please sign in again.'),
        findsOneWidget,
      );
    });

    group('a web page load while the session is still restoring', () {
      /// Opens the app at [location], as the browser's address bar would.
      void startAt(WidgetTester tester, String location) {
        tester.binding.platformDispatcher.defaultRouteNameTestValue = location;
        addTearDown(
          tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
        );
      }

      testWidgets('/register?invite=… comes back with the invite code', (
        tester,
      ) async {
        final store = _SlowTokenStore();
        final backend = TestBackend(store: store);
        startAt(tester, '/register?invite=ABCDEFGHJK');

        final container = await tester.pumpFriendsApp(
          overrides: backend.overrides,
          settle: false,
        );
        expect(container.read(authControllerProvider), isA<AuthUnknown>());
        expect(
          currentLocation(container),
          '/splash?from=%2Fregister%3Finvite%3DABCDEFGHJK',
        );

        store.release();
        await tester.pumpAndSettle();

        expect(currentLocation(container), '/register?invite=ABCDEFGHJK');
        expect(find.byType(RegisterScreen), findsOneWidget);
        expect(find.text('ABCDE-FGHJK'), findsOneWidget);
      });

      testWidgets('/login?from=… keeps its from while signed out', (
        tester,
      ) async {
        final store = _SlowTokenStore();
        final backend = TestBackend(store: store);
        startAt(tester, '/login?from=%2Fprofile');

        final container = await tester.pumpFriendsApp(
          overrides: backend.overrides,
          settle: false,
        );
        store.release();
        await tester.pumpAndSettle();

        expect(currentLocation(container), '/login?from=%2Fprofile');
        expect(find.byType(LoginScreen), findsOneWidget);
      });

      testWidgets('/login?from=… with a stored session goes to that from', (
        tester,
      ) async {
        final store = _SlowTokenStore('refresh-0');
        final backend = TestBackend(store: store)..stubRestore();
        startAt(tester, '/login?from=%2Fprofile');

        final container = await tester.pumpFriendsApp(
          overrides: backend.overrides,
          settle: false,
        );
        expect(container.read(authControllerProvider), isA<AuthUnknown>());

        store.release();
        await tester.pumpAndSettle();

        expect(currentLocation(container), '/profile');
        expect(find.byType(ProfileScreen), findsOneWidget);
      });
    });

    testWidgets('unknown locations show a not-found page', (tester) async {
      await tester.pumpFriendsApp(
        overrides: [
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedInState),
          ),
        ],
        location: '/nope',
      );

      expect(find.byType(NotFoundScreen), findsOneWidget);
    });
  });
}

/// A `TokenStore` whose reads wait for [release], like secure storage that
/// is slow at startup: the router runs while the state is [AuthUnknown].
class _SlowTokenStore extends InMemoryTokenStore {
  new([super.refreshToken]);

  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<String?> readRefreshToken() =>
      _gate.future.then((_) => super.readRefreshToken());
}
