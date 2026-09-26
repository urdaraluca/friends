import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/features/auth/presentation/login_screen.dart';
import 'package:friends/features/auth/presentation/register_screen.dart';
import 'package:friends/features/auth/presentation/splash_screen.dart';
import 'package:friends/features/health/presentation/health_screen.dart';
import 'package:friends/features/home/presentation/home_screen.dart';
import 'package:friends/features/invites/presentation/join_screen.dart';
import 'package:friends/features/profile/presentation/profile_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_router.g.dart';

/// Where [auth] sends a user who navigates to [uri], or null to stay.
///
/// - [AuthUnknown] → `/splash?from=…`, keeping the whole location, auth
///   screens included (every cold start begins here: a page load or reload
///   on web, a deep link).
/// - [Unauthenticated] → `/login?from=…`, except on the public routes
///   (`/login`, `/register`, `/join/:code`, `/health`). After an explicit
///   sign-out or account deletion it is plain `/login`: whoever signs in
///   next shouldn't land on the previous user's page. On `/splash`, a public
///   `from` is restored as it was (`/register?invite=…`).
/// - [Authenticated] on `/splash`, `/login` or `/register` → `from`, or `/`.
///   An auth screen in `from` is unwrapped to its own `from`
///   (`Routes.afterSignIn`).
@visibleForTesting
String? authRedirect(AuthState auth, Uri uri) {
  final path = uri.path;
  if (path == Routes.health) return null;
  final from = uri.queryParameters[Routes.fromParam];
  final here = uri.toString();
  switch (auth) {
    case AuthUnknown():
      return path == Routes.splash ? null : Routes.splashWith(from: here);
    case Unauthenticated(:final reason):
      if (path == Routes.splash) {
        final back = Routes.safeSplashFrom(from);
        return back != null && Routes.isPublic(Uri.parse(back).path)
            ? back
            : Routes.loginWith(from: back);
      }
      if (Routes.isPublic(path)) return null;
      final returnHere =
          reason == SignOutReason.noSession ||
          reason == SignOutReason.sessionExpired;
      return Routes.loginWith(from: returnHere ? here : null);
    case Authenticated():
      return Routes.isAuthOnly(path) ? Routes.afterSignIn(from) : null;
  }
}

/// The app's [GoRouter]. It re-runs [authRedirect] whenever the auth state
/// changes (`refreshListenable`), without being rebuilt itself.
@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final auth = ValueNotifier<AuthState>(ref.read(authControllerProvider));
  ref
    ..listen(authControllerProvider, (_, next) => auth.value = next)
    ..onDispose(auth.dispose);

  final router = GoRouter(
    refreshListenable: auth,
    redirect: (context, state) => authRedirect(auth.value, state.uri),
    errorBuilder: (context, state) => const NotFoundScreen(),
    routes: [
      GoRoute(
        path: Routes.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (context, state) =>
            LoginScreen(from: state.uri.queryParameters[Routes.fromParam]),
      ),
      GoRoute(
        path: Routes.register,
        builder: (context, state) => RegisterScreen(
          from: state.uri.queryParameters[Routes.fromParam],
          invite: state.uri.queryParameters[Routes.inviteParam],
        ),
      ),
      GoRoute(
        path: Routes.joinPattern,
        builder: (context, state) =>
            JoinScreen(code: state.pathParameters['code']!),
      ),
      GoRoute(
        path: Routes.profile,
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: Routes.health,
        builder: (context, state) => const HealthScreen(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
}

/// Unknown locations.
class NotFoundScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("This page doesn't exist."),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go(Routes.home),
              child: const Text('Go home'),
            ),
          ],
        ),
      ),
    );
  }
}
