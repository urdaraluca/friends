import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart' show Locale;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_locale.g.dart';

/// The languages the app speaks, as `Me.locale` stores them (BCP 47).
const appLanguages = {'en': 'English', 'ro': 'Română'};

/// The language chosen in the profile (`Me.locale`), or null to follow the
/// device. An unknown tag is ignored.
@riverpod
Locale? appLocale(Ref ref) {
  final tag = ref.watch(currentUserProvider)?.locale;
  if (tag == null) return null;
  final language = tag.split(RegExp('[-_]')).first.toLowerCase();
  return AppLocalizations.supportedLocales
      .where((locale) => locale.languageCode == language)
      .firstOrNull;
}
