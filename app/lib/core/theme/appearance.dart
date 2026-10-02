import 'dart:convert';

import 'package:friends/core/theme/app_palette.dart';
import 'package:friends/core/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'appearance.g.dart';

/// How the app looks on this device: light or dark, the colour palette, and
/// whether a group's screens take the group's colour.
@immutable
class AppearanceSettings {
  const new({
    this.mode = ThemeMode.system,
    this.palette = AppPalette.coral,
    this.customPrimary = customPrimaryDefault,
    this.customAccent = customAccentDefault,
    this.groupColors = true,
  });

  /// Parses what [toJson] wrote. Anything unknown or malformed falls back to
  /// its default.
  factory fromJson(Map<String, Object?> json) {
    final mode = json['mode'];
    final palette = json['palette'];
    final primary = json['primary'];
    final accent = json['accent'];
    return AppearanceSettings(
      mode:
          ThemeMode.values.where((m) => m.name == mode).firstOrNull ??
          ThemeMode.system,
      palette:
          AppPalette.values.where((p) => p.name == palette).firstOrNull ??
          AppPalette.coral,
      customPrimary:
          HexColor.tryParse(primary is String ? primary : null) ??
          customPrimaryDefault,
      customAccent:
          HexColor.tryParse(accent is String ? accent : null) ??
          customAccentDefault,
      groupColors: json['groupColors'] != false,
    );
  }

  final ThemeMode mode;
  final AppPalette palette;

  /// The custom palette's colours (kept when another palette is chosen).
  final Color customPrimary;
  final Color customAccent;

  /// Inside a group, use the group's own colour instead of [palette].
  final bool groupColors;

  /// The colours the app is themed with.
  PaletteColors get colors => palette == AppPalette.custom
      ? PaletteColors(customPrimary, accent: customAccent, white: true)
      : palette.colors;

  AppearanceSettings copyWith({
    ThemeMode? mode,
    AppPalette? palette,
    Color? customPrimary,
    Color? customAccent,
    bool? groupColors,
  }) => AppearanceSettings(
    mode: mode ?? this.mode,
    palette: palette ?? this.palette,
    customPrimary: customPrimary ?? this.customPrimary,
    customAccent: customAccent ?? this.customAccent,
    groupColors: groupColors ?? this.groupColors,
  );

  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'palette': palette.name,
    'primary': HexColor.format(customPrimary),
    'accent': HexColor.format(customAccent),
    'groupColors': groupColors,
  };

  @override
  bool operator ==(Object other) =>
      other is AppearanceSettings &&
      other.mode == mode &&
      other.palette == palette &&
      other.customPrimary == customPrimary &&
      other.customAccent == customAccent &&
      other.groupColors == groupColors;

  @override
  int get hashCode =>
      Object.hash(mode, palette, customPrimary, customAccent, groupColors);
}

/// Keeps [AppearanceSettings] on this device.
abstract interface class AppearanceStore {
  /// The saved settings, or null when there are none.
  Future<AppearanceSettings?> read();

  Future<void> write(AppearanceSettings settings);
}

/// [AppearanceStore] on `SharedPreferencesAsync`.
///
/// Best effort: a storage failure (or a platform without the plugin, as in
/// widget tests) reads as "nothing saved" and drops writes.
class SharedPrefsAppearanceStore implements AppearanceStore {
  new([SharedPreferencesAsync? prefs]) : _prefs = prefs;

  static const _key = 'friends.appearance';

  SharedPreferencesAsync? _prefs;

  SharedPreferencesAsync get _store => _prefs ??= SharedPreferencesAsync();

  @override
  Future<AppearanceSettings?> read() async {
    try {
      final saved = await _store.getString(_key);
      if (saved == null) return null;
      final json = jsonDecode(saved);
      return json is Map<String, Object?>
          ? AppearanceSettings.fromJson(json)
          : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(AppearanceSettings settings) async {
    try {
      await _store.setString(_key, jsonEncode(settings.toJson()));
    } on Object {
      // Best effort.
    }
  }
}

/// The app-wide [AppearanceStore]. Tests override it with an in-memory
/// store.
@Riverpod(keepAlive: true)
AppearanceStore appearanceStore(Ref ref) => SharedPrefsAppearanceStore();

/// The settings saved on this device, read by `main` before the first frame
/// (so the app never flashes the default colours).
@Riverpod(keepAlive: true)
AppearanceSettings initialAppearance(Ref ref) => const AppearanceSettings();

/// The current [AppearanceSettings]; [set] applies and saves new ones.
@Riverpod(keepAlive: true)
class Appearance extends _$Appearance {
  @override
  AppearanceSettings build() => ref.watch(initialAppearanceProvider);

  Future<void> set(AppearanceSettings settings) async {
    state = settings;
    await ref.read(appearanceStoreProvider).write(settings);
  }
}
