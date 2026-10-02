import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/theme/app_palette.dart';
import 'package:friends/core/theme/app_theme.dart';
import 'package:friends/core/theme/appearance.dart';
import 'package:friends/features/profile/presentation/appearance_screen.dart';
import 'package:friends/features/profile/presentation/widgets/theme_preview.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/test_backend.dart';

void main() {
  late TestBackend backend;

  /// Signs in by restoring a stored session, then opens [location] on a
  /// screen tall enough to show everything.
  Future<ProviderContainer> open(
    WidgetTester tester, {
    String location = '/appearance',
    AppearanceSettings? saved,
    double width = 800,
    String? locale,
  }) async {
    tester.view
      ..physicalSize = Size(width, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    backend = TestBackend(storedRefreshToken: 'refresh-0')
      ..stubRestore(me: meJson(locale: locale));
    return await tester.pumpFriendsApp(
      overrides: [
        ...backend.overrides,
        if (saved != null) initialAppearanceProvider.overrideWithValue(saved),
      ],
      location: location,
    );
  }

  MaterialApp app(WidgetTester tester) =>
      tester.widget<MaterialApp>(find.byType(MaterialApp));

  ThemeData previewTheme(WidgetTester tester) =>
      tester.widget<ThemePreview>(find.byType(ThemePreview)).theme;

  VoidCallback? applyButton(WidgetTester tester) => tester
      .widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'))
      .onPressed;

  testWidgets('the profile links to Appearance', (tester) async {
    await open(tester, location: '/profile');

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();

    expect(find.byType(AppearanceScreen), findsOneWidget);
  });

  testWidgets('previews a palette, then applies and saves it', (tester) async {
    await open(tester);
    final royal = AppTheme.of(AppPalette.royal.colors, Brightness.light);
    expect(applyButton(tester), isNull);

    await tester.tap(find.text('Royal'));
    await tester.pumpAndSettle();

    // Only the preview changes until Apply.
    expect(previewTheme(tester), same(royal));
    expect(app(tester).theme, isNot(same(royal)));
    expect(backend.appearance.settings, isNull);

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(app(tester).theme, same(royal));
    expect(
      backend.appearance.settings,
      const AppearanceSettings(palette: AppPalette.royal),
    );
    expect(find.text('Appearance saved'), findsOneWidget);
    expect(applyButton(tester), isNull);
  });

  testWidgets('switches to dark mode', (tester) async {
    await open(tester);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(previewTheme(tester).brightness, Brightness.dark);

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(app(tester).themeMode, ThemeMode.dark);
    expect(backend.appearance.settings?.mode, ThemeMode.dark);
  });

  testWidgets('picks custom colours', (tester) async {
    await open(tester);
    expect(find.text('Main colour'), findsNothing);

    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    expect(find.text('Main colour'), findsOneWidget);

    // The main colour's swatches come first, then the accent's.
    await tester.tap(find.byTooltip('Green').first);
    await tester.tap(find.byTooltip('Orange').last);
    await tester.pumpAndSettle();

    const colors = PaletteColors(
      Color(0xFF2E7D32),
      accent: Color(0xFFEF6C00),
      white: true,
    );
    expect(previewTheme(tester), same(AppTheme.of(colors, Brightness.light)));

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(backend.appearance.settings?.colors, colors);
  });

  testWidgets('turns group colours off', (tester) async {
    await open(tester);

    await tester.tap(find.text('Group colours'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(backend.appearance.settings?.groupColors, isFalse);
  });

  testWidgets('starts with the saved settings, and resets to the defaults', (
    tester,
  ) async {
    const saved = AppearanceSettings(
      mode: ThemeMode.dark,
      palette: AppPalette.lavender,
    );
    await open(tester, saved: saved);

    final lavender = AppPalette.lavender.colors;
    expect(app(tester).themeMode, ThemeMode.dark);
    expect(app(tester).darkTheme, same(AppTheme.of(lavender, Brightness.dark)));
    expect(previewTheme(tester), same(AppTheme.of(lavender, Brightness.dark)));

    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(backend.appearance.settings, const AppearanceSettings());
    expect(app(tester).themeMode, ThemeMode.system);
  });

  testWidgets('fits a phone, in Romanian too', (tester) async {
    // A layout overflow fails the test.
    await open(tester, width: 360, locale: 'ro');

    await tester.tap(find.text('Personalizat'));
    await tester.tap(find.text('Întunecat'));
    await tester.pumpAndSettle();

    expect(find.text('Culoarea de accent'), findsOneWidget);
    expect(previewTheme(tester).brightness, Brightness.dark);
  });
}
