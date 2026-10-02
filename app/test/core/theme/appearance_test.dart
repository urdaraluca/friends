import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/theme/app_palette.dart';
import 'package:friends/core/theme/app_theme.dart';
import 'package:friends/core/theme/appearance.dart';
import 'package:friends/features/groups/presentation/widgets/group_themed.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/pump_app.dart';

/// String storage in memory (only what the appearance store uses).
class _StringPrefs implements SharedPreferencesAsync {
  final data = <String, String>{};

  @override
  Future<String?> getString(String key) async => data[key];

  @override
  Future<void> setString(String key, String value) async => data[key] = value;

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

double _hue(Color color) => HSVColor.fromColor(color).hue;

void main() {
  group('AppearanceSettings', () {
    test('round-trips through JSON', () {
      const settings = AppearanceSettings(
        mode: ThemeMode.dark,
        palette: AppPalette.custom,
        customPrimary: Color(0xFF2E7D32),
        customAccent: Color(0xFFFFB300),
        groupColors: false,
      );
      expect(settings.toJson(), {
        'mode': 'dark',
        'palette': 'custom',
        'primary': '#2E7D32',
        'accent': '#FFB300',
        'groupColors': false,
      });
      expect(AppearanceSettings.fromJson(settings.toJson()), settings);
    });

    test('falls back to the defaults for anything unknown', () {
      expect(
        AppearanceSettings.fromJson(const {
          'mode': 'sepia',
          'palette': 'neon',
          'primary': 'purple',
          'accent': 7,
        }),
        const AppearanceSettings(),
      );
    });

    test('the custom palette uses the picked colours on white', () {
      const settings = AppearanceSettings(
        palette: AppPalette.custom,
        customPrimary: Color(0xFF1565C0),
        customAccent: Color(0xFFEF6C00),
      );
      expect(
        settings.colors,
        const PaletteColors(
          Color(0xFF1565C0),
          accent: Color(0xFFEF6C00),
          white: true,
        ),
      );
      expect(
        settings.copyWith(palette: AppPalette.royal).colors,
        AppPalette.royal.colors,
      );
    });
  });

  group('SharedPrefsAppearanceStore', () {
    test('saves and reads the settings', () async {
      final prefs = _StringPrefs();
      final store = SharedPrefsAppearanceStore(prefs);
      expect(await store.read(), isNull);

      const settings = AppearanceSettings(palette: AppPalette.royal);
      await store.write(settings);

      expect(jsonDecode(prefs.data['friends.appearance']!), settings.toJson());
      expect(await store.read(), settings);
    });

    test('reads garbage as nothing saved', () async {
      final prefs = _StringPrefs()..data['friends.appearance'] = '[1, 2]';
      expect(await SharedPrefsAppearanceStore(prefs).read(), isNull);
      prefs.data['friends.appearance'] = '{oops';
      expect(await SharedPrefsAppearanceStore(prefs).read(), isNull);
    });
  });

  group('AppTheme', () {
    test('coral, the default, is the original single-seed look', () {
      final theme = AppTheme.of(AppPalette.coral.colors, Brightness.light);
      expect(
        theme.colorScheme,
        ColorScheme.fromSeed(seedColor: const Color(0xFFFF7A59)),
      );
      expect(theme.floatingActionButtonTheme.backgroundColor, isNull);
    });

    test('royal is purple and yellow on white', () {
      final light = AppTheme.of(AppPalette.royal.colors, Brightness.light);
      final scheme = light.colorScheme;
      expect(_hue(scheme.primary), inInclusiveRange(270, 300));
      expect(_hue(scheme.secondaryContainer), inInclusiveRange(40, 55));
      expect(scheme.tertiaryContainer, scheme.secondaryContainer);
      expect(scheme.surface, Colors.white);
      // FABs wear the accent.
      expect(
        light.floatingActionButtonTheme.backgroundColor,
        scheme.secondaryContainer,
      );

      final dark = AppTheme.of(AppPalette.royal.colors, Brightness.dark);
      expect(dark.colorScheme.brightness, Brightness.dark);
      expect(dark.colorScheme.surface, isNot(Colors.white));
      expect(
        _hue(dark.colorScheme.secondaryContainer),
        inInclusiveRange(40, 55),
      );
    });

    test('every palette is cached per brightness', () {
      for (final palette in AppPalette.values) {
        expect(
          AppTheme.of(palette.colors, Brightness.dark),
          same(AppTheme.of(palette.colors, Brightness.dark)),
        );
      }
    });
  });

  group('GroupColorTheme', () {
    Future<ColorScheme> schemeInside(
      WidgetTester tester, {
      required bool groupColors,
    }) async {
      late ColorScheme scheme;
      await tester.pumpApp(
        GroupColorTheme(
          color: '#43A047',
          child: Builder(
            builder: (context) {
              scheme = Theme.of(context).colorScheme;
              return const SizedBox();
            },
          ),
        ),
        overrides: [
          initialAppearanceProvider.overrideWithValue(
            AppearanceSettings(groupColors: groupColors),
          ),
        ],
      );
      return scheme;
    }

    testWidgets('applies the group colour', (tester) async {
      final scheme = await schemeInside(tester, groupColors: true);
      expect(
        scheme,
        AppTheme.seededFrom(
          const Color(0xFF43A047),
          Brightness.light,
        ).colorScheme,
      );
    });

    testWidgets('keeps the app theme when group colours are off', (
      tester,
    ) async {
      final scheme = await schemeInside(tester, groupColors: false);
      expect(_hue(scheme.primary), isNot(inInclusiveRange(90, 150)));
    });
  });

  test('the appearance provider starts from the saved settings', () {
    const saved = AppearanceSettings(palette: AppPalette.ocean);
    final container = ProviderContainer.test(
      overrides: [initialAppearanceProvider.overrideWithValue(saved)],
    );
    expect(container.read(appearanceProvider), saved);
  });
}
