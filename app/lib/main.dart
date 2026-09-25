import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:friends/app.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  usePathUrlStrategy();
  runApp(
    ProviderScope(
      // Failed requests surface immediately; the UI offers an explicit retry.
      retry: (retryCount, error) => null,
      child: const FriendsApp(),
    ),
  );
}
