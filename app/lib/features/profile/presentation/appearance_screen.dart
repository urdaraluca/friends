import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/core/theme/app_palette.dart';
import 'package:friends/core/theme/app_theme.dart';
import 'package:friends/core/theme/appearance.dart';
import 'package:friends/features/profile/presentation/widgets/theme_preview.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Appearance: light or dark, the colour palette (or custom colours) and
/// group colours, tried out in a preview before they are applied.
class AppearanceScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends ConsumerState<AppearanceScreen> {
  late AppearanceSettings _draft = ref.read(appearanceProvider);

  void _update(AppearanceSettings draft) => setState(() => _draft = draft);

  Future<void> _apply() async {
    await ref.read(appearanceProvider.notifier).set(_draft);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.l10n.appearanceSaved)));
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(appearanceProvider);
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    final brightness = switch (_draft.mode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };
    return Scaffold(
      appBar: AppBar(
        // Opened directly (a deep link): nothing to pop.
        leading: context.canPop()
            ? null
            : IconButton(
                tooltip: l10n.home,
                icon: const Icon(Icons.home_outlined),
                onPressed: () => context.go(Routes.home),
              ),
        title: Text(l10n.appearance),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(l10n.appearancePreview, style: textTheme.titleMedium),
              Text(l10n.appearancePreviewHelp, style: textTheme.bodySmall),
              const SizedBox(height: 8),
              ThemePreview(theme: AppTheme.of(_draft.colors, brightness)),
              const SizedBox(height: 24),
              Text(l10n.themeModeLabel, style: textTheme.titleMedium),
              const SizedBox(height: 8),
              SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: const Icon(Icons.brightness_auto_outlined),
                    label: Text(l10n.themeModeSystem),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: const Icon(Icons.light_mode_outlined),
                    label: Text(l10n.themeModeLight),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: const Icon(Icons.dark_mode_outlined),
                    label: Text(l10n.themeModeDark),
                  ),
                ],
                selected: {_draft.mode},
                onSelectionChanged: (modes) =>
                    _update(_draft.copyWith(mode: modes.single)),
              ),
              const SizedBox(height: 24),
              Text(l10n.colourPaletteLabel, style: textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final palette in AppPalette.values)
                    _PaletteTile(
                      label: palette.label(l10n),
                      colors: _draft.copyWith(palette: palette).colors,
                      selected: _draft.palette == palette,
                      onTap: () => _update(_draft.copyWith(palette: palette)),
                    ),
                ],
              ),
              if (_draft.palette == AppPalette.custom) ...[
                const SizedBox(height: 16),
                Text(l10n.mainColour, style: textTheme.labelLarge),
                const SizedBox(height: 8),
                _Swatches(
                  selected: _draft.customPrimary,
                  onSelected: (color) =>
                      _update(_draft.copyWith(customPrimary: color)),
                ),
                const SizedBox(height: 16),
                Text(l10n.accentColour, style: textTheme.labelLarge),
                const SizedBox(height: 8),
                _Swatches(
                  selected: _draft.customAccent,
                  onSelected: (color) =>
                      _update(_draft.copyWith(customAccent: color)),
                ),
              ],
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.groupColoursToggle),
                subtitle: Text(l10n.groupColoursHelp),
                value: _draft.groupColors,
                onChanged: (value) =>
                    _update(_draft.copyWith(groupColors: value)),
              ),
              Text(l10n.appearanceDeviceNote, style: textTheme.bodySmall),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _draft == const AppearanceSettings()
                    ? null
                    : () => _update(const AppearanceSettings()),
                child: Text(l10n.resetAppearance),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _draft == saved ? null : () => unawaited(_apply()),
                child: Text(l10n.apply),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A palette to pick: its main, accent and background colours, and its
/// name.
class _PaletteTile extends StatelessWidget {
  const new({
    required this.label,
    required this.colors,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final PaletteColors colors;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = AppTheme.of(colors, Brightness.light).colorScheme;
    final dots = [scheme.primary, scheme.secondaryContainer, scheme.surface];
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: selected
              ? BorderSide(color: theme.colorScheme.primary, width: 2)
              : BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 100,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              child: Column(
                children: [
                  SizedBox(
                    width: 60,
                    height: 28,
                    child: Stack(
                      children: [
                        for (final (i, color) in dots.indexed)
                          Positioned(
                            left: i * 16,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (selected) ...[
                        Icon(
                          Icons.check,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 2),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The custom palette's colour choices; a saved colour that isn't one of
/// them is kept as an extra swatch.
class _Swatches extends StatelessWidget {
  const new({required this.selected, required this.onSelected});

  final Color selected;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    final selectedHex = HexColor.format(selected);
    final swatches = {
      if (!customPaletteSwatches.containsKey(selectedHex))
        selectedHex: context.l10n.currentColour,
      ...customPaletteSwatches,
    };
    final outline = Theme.of(context).colorScheme.onSurface;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final MapEntry(key: hex, value: name) in swatches.entries)
          if (HexColor.tryParse(hex) case final color?)
            Semantics(
              button: true,
              selected: hex == selectedHex,
              label: name,
              child: Tooltip(
                message: name,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => onSelected(color),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: hex == selectedHex
                          ? Border.all(color: outline, width: 3)
                          : null,
                    ),
                    child: hex == selectedHex
                        ? Icon(
                            Icons.check,
                            // Dark on the light swatches (yellow, amber).
                            color:
                                ThemeData.estimateBrightnessForColor(color) ==
                                    Brightness.dark
                                ? Colors.white
                                : Colors.black87,
                          )
                        : null,
                  ),
                ),
              ),
            ),
      ],
    );
  }
}
