import 'package:friends/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// A small mock of a group's screen in [theme], for Appearance: an app bar,
/// an activity card, chips, buttons, a FAB and the bottom tabs. It doesn't
/// react to taps.
class ThemePreview extends StatelessWidget {
  const new({required this.theme, super.key});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: theme,
      child: Builder(
        builder: (context) {
          final colors = Theme.of(context).colorScheme;
          final l10n = context.l10n;
          return IgnorePointer(
            child: ExcludeFocus(
              child: Material(
                color: colors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colors.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppBar(
                      primary: false,
                      automaticallyImplyLeading: false,
                      title: Text(l10n.previewGroupName),
                      actions: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: colors.primary,
                          foregroundColor: colors.onPrimary,
                          child: const Text('A'),
                        ),
                        const SizedBox(width: 12),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Card(
                            margin: EdgeInsets.zero,
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: colors.secondaryContainer,
                                foregroundColor: colors.onSecondaryContainer,
                                child: const Icon(Icons.extension),
                              ),
                              title: Text(l10n.previewActivity),
                              subtitle: Text(l10n.previewWhen),
                              trailing: Icon(
                                Icons.star,
                                color: colors.tertiary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilterChip(
                                selected: true,
                                label: Text(l10n.statusIdea),
                                onSelected: (_) {},
                              ),
                              FilterChip(
                                label: Text(l10n.statusScheduled),
                                onSelected: (_) {},
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              // The buttons wrap on a narrow phone.
                              Expanded(
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    FilledButton(
                                      onPressed: () {},
                                      child: Text(l10n.spin),
                                    ),
                                    OutlinedButton(
                                      onPressed: () {},
                                      child: Text(l10n.vote),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              FloatingActionButton.small(
                                heroTag: null,
                                onPressed: () {},
                                child: const Icon(Icons.add),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    NavigationBar(
                      height: 64,
                      destinations: [
                        NavigationDestination(
                          icon: const Icon(Icons.checklist),
                          label: l10n.tabBacklog,
                        ),
                        NavigationDestination(
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: l10n.tabCalendar,
                        ),
                        NavigationDestination(
                          icon: const Icon(Icons.casino_outlined),
                          label: l10n.tabWheel,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
