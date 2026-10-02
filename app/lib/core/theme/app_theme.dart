import 'package:friends/core/theme/app_palette.dart';
import 'package:material_ui/material_ui.dart';

abstract final class AppTheme {
  static final _themes = <(PaletteColors, Brightness), ThemeData>{};

  static final _seeded = <(int, Brightness), ThemeData>{};

  /// The app theme for [colors]. Cached per palette and brightness.
  static ThemeData of(PaletteColors colors, Brightness brightness) =>
      _themes.putIfAbsent((colors, brightness), () {
        final scheme = schemeOf(colors, brightness);
        return ThemeData(
          colorScheme: scheme,
          // With an accent, FABs wear it (purple and gold, not purple on
          // purple).
          floatingActionButtonTheme: colors.accent == null
              ? null
              : FloatingActionButtonThemeData(
                  backgroundColor: scheme.secondaryContainer,
                  foregroundColor: scheme.onSecondaryContainer,
                ),
        );
      });

  /// The colour scheme for [colors].
  ///
  /// One colour is a plain seeded scheme (the original coral look). With an
  /// accent, both are seeded with the fidelity variant, which keeps their
  /// own vividness, and the accent's primary roles become the secondary and
  /// tertiary ones.
  static ColorScheme schemeOf(PaletteColors colors, Brightness brightness) {
    final accent = colors.accent;
    if (accent == null) {
      return ColorScheme.fromSeed(
        seedColor: colors.primary,
        brightness: brightness,
      );
    }
    final main = ColorScheme.fromSeed(
      seedColor: colors.primary,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    final second = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    final scheme = main.copyWith(
      secondary: second.primary,
      onSecondary: second.onPrimary,
      secondaryContainer: second.primaryContainer,
      onSecondaryContainer: second.onPrimaryContainer,
      tertiary: second.primary,
      onTertiary: second.onPrimary,
      tertiaryContainer: second.primaryContainer,
      onTertiaryContainer: second.onPrimaryContainer,
    );
    if (!colors.white || brightness == Brightness.dark) return scheme;
    return scheme.copyWith(
      surface: Colors.white,
      surfaceContainerLowest: Colors.white,
    );
  }

  /// The app theme seeded from a group's [color]. Cached per colour and
  /// brightness.
  static ThemeData seededFrom(Color color, Brightness brightness) =>
      _seeded.putIfAbsent(
        (color.toARGB32(), brightness),
        () => ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: color,
            brightness: brightness,
          ),
        ),
      );
}

/// `#RRGGBB` colours as the API sends them (contract section 1.4).
abstract final class HexColor {
  static final _pattern = RegExp(r'^#[0-9A-Fa-f]{6}$');

  /// [hex] as an opaque [Color], or null when it isn't `#RRGGBB`.
  static Color? tryParse(String? hex) {
    if (hex == null || !_pattern.hasMatch(hex)) return null;
    return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
  }

  /// [color] as `#RRGGBB` (uppercase, like the server stores it).
  static String format(Color color) {
    final rgb = color.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}
