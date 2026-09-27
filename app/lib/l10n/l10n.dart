import 'package:friends/l10n/generated/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

export 'package:friends/l10n/generated/app_localizations.dart';

/// The app's strings in the current locale: `context.l10n.save`.
extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Every delegate the app needs: its own strings, then material_ui's (which
/// include the widgets and Cupertino ones).
const List<LocalizationsDelegate<Object?>> appLocalizationsDelegates = [
  AppLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
];

/// The strings for the app's current language (`Intl.defaultLocale`, which
/// `FriendsApp` keeps in step), for code without a [BuildContext]: error
/// messages, validators, labels of enums.
AppLocalizations get currentL10n {
  final language = Intl.getCurrentLocale().split(RegExp('[-_]')).first;
  final supported = AppLocalizations.supportedLocales.any(
    (locale) => locale.languageCode == language,
  );
  return lookupAppLocalizations(Locale(supported ? language : 'en'));
}
