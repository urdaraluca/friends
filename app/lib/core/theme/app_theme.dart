import 'package:material_ui/material_ui.dart';

abstract final class AppTheme {
  static const Color seed = Color(0xFFFF7A59);

  static final ThemeData light = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: seed),
  );

  static final ThemeData dark = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ),
  );

  static final _seeded = <(int, Brightness), ThemeData>{};

  /// The app theme seeded from [color] (a group's colour), or the default
  /// theme when [color] is null. Cached per colour and brightness.
  static ThemeData seededFrom(Color? color, Brightness brightness) {
    if (color == null) return brightness == Brightness.dark ? dark : light;
    return _seeded.putIfAbsent(
      (color.toARGB32(), brightness),
      () => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: color,
          brightness: brightness,
        ),
      ),
    );
  }
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
