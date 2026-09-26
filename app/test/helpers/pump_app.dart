import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/app.dart';
import 'package:friends/core/router/app_router.dart';
import 'package:material_ui/material_ui.dart';

extension PumpApp on WidgetTester {
  /// Pumps [widget] as the home of a plain [MaterialApp] (no router).
  Future<void> pumpApp(Widget widget, {List<Override> overrides = const []}) {
    return pumpWidget(
      ProviderScope(
        overrides: overrides,
        retry: (retryCount, error) => null,
        child: MaterialApp(home: widget),
      ),
    );
  }

  /// Pumps the whole app (router included), navigates to [location] if
  /// given, and returns the provider container.
  ///
  /// Pass `settle: false` when a spinner stays on screen (the splash screen
  /// while restoring), since `pumpAndSettle` would time out; the app is then
  /// pumped a few frames instead.
  Future<ProviderContainer> pumpFriendsApp({
    List<Override> overrides = const [],
    String? location,
    bool settle = true,
  }) async {
    await pumpWidget(
      ProviderScope(
        overrides: overrides,
        retry: (retryCount, error) => null,
        child: const FriendsApp(),
      ),
    );
    final container = ProviderScope.containerOf(
      element(find.byType(FriendsApp)),
    );
    if (location != null) container.read(routerProvider).go(location);
    if (settle) {
      await pumpAndSettle();
    } else {
      await pumpFrames(3);
    }
    return container;
  }

  /// Pumps [count] frames of 100 ms each.
  Future<void> pumpFrames(int count) async {
    for (var i = 0; i < count; i++) {
      await pump(const Duration(milliseconds: 100));
    }
  }
}

/// The router's current location, e.g. `/login?from=%2Fprofile`.
String currentLocation(ProviderContainer container) =>
    container.read(routerProvider).state.uri.toString();
