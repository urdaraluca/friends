import 'package:friends/core/api/generated/export.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// How the app names and shows each [GroupKind].
extension GroupKindLabels on GroupKind {
  String get label => switch (this) {
    GroupKind.movieNight => currentL10n.groupKindMovieNight,
    GroupKind.bookClub => currentL10n.groupKindBookClub,
    GroupKind.general || GroupKind.$unknown => currentL10n.groupKindGeneral,
  };

  /// What the kind gives the group, in a sentence.
  String get help => switch (this) {
    GroupKind.movieNight => currentL10n.groupKindMovieNightHelp,
    GroupKind.bookClub => currentL10n.groupKindBookClubHelp,
    GroupKind.general || GroupKind.$unknown => currentL10n.groupKindGeneralHelp,
  };

  IconData get icon => switch (this) {
    GroupKind.movieNight => Icons.movie_outlined,
    GroupKind.bookClub => Icons.menu_book_outlined,
    GroupKind.general || GroupKind.$unknown => Icons.groups_outlined,
  };
}
