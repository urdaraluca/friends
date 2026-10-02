import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:friends/app.dart';
import 'package:friends/core/theme/appearance.dart';
import 'package:material_ui/material_ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  // Read before the first frame, so the saved colours show from the start.
  final appearance = await SharedPrefsAppearanceStore().read();
  runApp(
    ProviderScope(
      overrides: [
        if (appearance != null)
          initialAppearanceProvider.overrideWithValue(appearance),
      ],
      // Failed requests surface immediately; the UI offers an explicit retry.
      retry: (retryCount, error) => null,
      child: const FriendsApp(),
    ),
  );
}
