import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/i18n/app_locale.dart';
import 'package:friends/core/router/app_router.dart';
import 'package:friends/core/theme/app_theme.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

class FriendsApp extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // The profile's language, else the device's (English when the device
      // speaks neither).
      locale: ref.watch(appLocaleProvider),
      builder: (context, child) {
        // `DateFormat` and `NumberFormat` without an explicit locale follow
        // the app's.
        Intl.defaultLocale = Localizations.localeOf(context).toLanguageTag();
        return child!;
      },
      routerConfig: ref.watch(routerProvider),
    );
  }
}
