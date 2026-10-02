import 'package:friends/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// The colours a theme is built from: a main colour, an optional accent
/// (secondary, tertiary and the FAB), and whether light surfaces are plain
/// white instead of tinted with the main colour.
@immutable
class PaletteColors {
  const new(this.primary, {this.accent, this.white = false});

  final Color primary;
  final Color? accent;
  final bool white;

  @override
  bool operator ==(Object other) =>
      other is PaletteColors &&
      other.primary == primary &&
      other.accent == accent &&
      other.white == white;

  @override
  int get hashCode => Object.hash(primary, accent, white);
}

/// The colour sets offered in Appearance. [coral] is the default (the app's
/// original look); [custom] takes its colours from the user's picks, and its
/// own are the picks' defaults.
enum AppPalette {
  coral(PaletteColors(Color(0xFFFF7A59))),
  royal(
    PaletteColors(Color(0xFF6A1B9A), accent: Color(0xFFFFC400), white: true),
  ),
  lavender(
    PaletteColors(Color(0xFF7E57C2), accent: Color(0xFFFFEB3B), white: true),
  ),
  ocean(
    PaletteColors(Color(0xFF1565C0), accent: Color(0xFF00BFA5), white: true),
  ),
  forest(PaletteColors(Color(0xFF2E7D32), accent: Color(0xFFFFA000))),
  sunset(PaletteColors(Color(0xFFE64A19), accent: Color(0xFFAD1457))),
  bubblegum(
    PaletteColors(Color(0xFFEC407A), accent: Color(0xFF26C6DA), white: true),
  ),
  midnight(PaletteColors(Color(0xFF283593), accent: Color(0xFF00B8D4))),
  graphite(
    PaletteColors(Color(0xFF455A64), accent: Color(0xFFFF7043), white: true),
  ),
  custom(
    PaletteColors(
      customPrimaryDefault,
      accent: customAccentDefault,
      white: true,
    ),
  );

  new(this.colors);

  final PaletteColors colors;

  /// The palette's name, in the app's language.
  String label(AppLocalizations l10n) => switch (this) {
    coral => l10n.paletteCoral,
    royal => l10n.paletteRoyal,
    lavender => l10n.paletteLavender,
    ocean => l10n.paletteOcean,
    forest => l10n.paletteForest,
    sunset => l10n.paletteSunset,
    bubblegum => l10n.paletteBubblegum,
    midnight => l10n.paletteMidnight,
    graphite => l10n.paletteGraphite,
    custom => l10n.paletteCustom,
  };
}

/// The custom palette's colours until the user picks others: purple and
/// yellow.
const customPrimaryDefault = Color(0xFF6A1B9A);
const customAccentDefault = Color(0xFFFFD600);

/// The colours offered for a custom palette, as `#RRGGBB` with a name for
/// screen readers, in the app's language.
Map<String, String> get customPaletteSwatches {
  final l10n = currentL10n;
  return {
    '#FF7A59': l10n.colourCoral,
    '#E53935': l10n.colourRed,
    '#EF6C00': l10n.colourOrange,
    '#FFB300': l10n.colourAmber,
    '#FFD600': l10n.colourYellow,
    '#2E7D32': l10n.colourGreen,
    '#00897B': l10n.colourTeal,
    '#1565C0': l10n.colourBlue,
    '#6A1B9A': l10n.colourPurple,
    '#D81B60': l10n.colourPink,
    '#6D4C41': l10n.colourBrown,
    '#546E7A': l10n.colourGrey,
  };
}
