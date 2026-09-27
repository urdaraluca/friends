import 'package:friends/l10n/l10n.dart';

/// The colours offered for a group, as `#RRGGBB` (uppercase, as the server
/// stores them) with a name for screen readers, in the app's language. The
/// first is the default for a new group.
Map<String, String> get groupColorPresets {
  final l10n = currentL10n;
  return {
    '#FF7A59': l10n.colourCoral,
    '#E53935': l10n.colourRed,
    '#F4B400': l10n.colourAmber,
    '#43A047': l10n.colourGreen,
    '#00897B': l10n.colourTeal,
    '#1E88E5': l10n.colourBlue,
    '#5E35B1': l10n.colourPurple,
    '#D81B60': l10n.colourPink,
  };
}
