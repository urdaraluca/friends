import 'package:friends/core/api/generated/export.dart';
import 'package:friends/l10n/l10n.dart';

/// The genres a member can pick, in the order the form lists them.
const List<BookGenre> bookGenres = [
  BookGenre.fiction,
  BookGenre.classics,
  BookGenre.fantasy,
  BookGenre.sciFi,
  BookGenre.mysteryThriller,
  BookGenre.romance,
  BookGenre.horror,
  BookGenre.youngAdult,
  BookGenre.children,
  BookGenre.comics,
  BookGenre.poetry,
  BookGenre.history,
  BookGenre.biography,
  BookGenre.nonFiction,
  BookGenre.selfHelp,
  BookGenre.other,
];

/// How the app names each [BookGenre].
extension BookGenreLabels on BookGenre {
  String get label => switch (this) {
    BookGenre.fiction => currentL10n.genreFiction,
    BookGenre.fantasy => currentL10n.genreFantasy,
    BookGenre.sciFi => currentL10n.genreSciFi,
    BookGenre.mysteryThriller => currentL10n.genreMysteryThriller,
    BookGenre.romance => currentL10n.genreRomance,
    BookGenre.horror => currentL10n.genreHorror,
    BookGenre.classics => currentL10n.genreClassics,
    BookGenre.history => currentL10n.genreHistory,
    BookGenre.biography => currentL10n.genreBiography,
    BookGenre.nonFiction => currentL10n.genreNonFiction,
    BookGenre.selfHelp => currentL10n.genreSelfHelp,
    BookGenre.poetry => currentL10n.genrePoetry,
    BookGenre.children => currentL10n.genreChildren,
    BookGenre.youngAdult => currentL10n.genreYoungAdult,
    BookGenre.comics => currentL10n.genreComics,
    BookGenre.other || BookGenre.$unknown => currentL10n.genreOther,
  };
}
