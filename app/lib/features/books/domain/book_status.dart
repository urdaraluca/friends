import 'package:friends/core/api/generated/export.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:intl/intl.dart';

/// The archive's quick filters, applied on the device (the API returns the
/// whole archive).
enum BookFilter {
  all,
  available,
  mine,
  withMe,
  waiting;

  String get label => switch (this) {
    all => currentL10n.bookFilterAll,
    available => currentL10n.bookFilterAvailable,
    mine => currentL10n.bookFilterMine,
    withMe => currentL10n.bookFilterWithMe,
    waiting => currentL10n.bookFilterWaiting,
  };

  /// Whether [book] passes, for the signed-in user [me].
  bool matches(Book book, String? me) => switch (this) {
    all => true,
    available => book.holder == null,
    mine => book.owner?.id == me,
    withMe => book.holder?.id == me,
    waiting => book.inMyQueue,
  };
}

/// Whether [book]'s title or author contains [query] (case-insensitive), or
/// its ISBN does (hyphens and spaces ignored); a blank query matches
/// everything.
bool bookMatchesQuery(Book book, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final digits = q.replaceAll(RegExp(r'[\s-]'), '');
  return book.title.toLowerCase().contains(q) ||
      (book.author?.toLowerCase().contains(q) ?? false) ||
      (digits.length >= 4 && (book.isbn?.contains(digits) ?? false));
}

/// How the archive is ordered.
enum BookSort {
  /// By title, as the API returns it.
  title,

  /// Best rated first (by average, then by how many rated it); unrated books
  /// last, by title.
  rating;

  String get label => switch (this) {
    title => currentL10n.bookSortTitle,
    rating => currentL10n.bookSortRating,
  };

  /// [books] (in title order) in this order.
  List<Book> apply(List<Book> books) => switch (this) {
    title => books,
    rating => [...books]..sort(_byRating),
  };
}

int _byRating(Book a, Book b) {
  final byAverage = (b.ratingAverage ?? -1).compareTo(a.ratingAverage ?? -1);
  if (byAverage != 0) return byAverage;
  final byCount = b.ratingCount.compareTo(a.ratingCount);
  if (byCount != 0) return byCount;
  // List.sort isn't stable: keep title order among equals.
  return a.title.toLowerCase().compareTo(b.title.toLowerCase());
}

/// "4.3" for a rating average, in the current locale.
String formatRating(num average) =>
    NumberFormat('0.0', currentL10n.localeName).format(average);

/// My place in [book]'s queue (from 1), or null when I'm not in it.
int? queuePosition(Book book, String? me) {
  final index = book.queue.indexWhere((entry) => entry.user.id == me);
  return index < 0 ? null : index + 1;
}

/// Who has [book] now, for [me]: "Available, with Ana", "Bogdan has it" or
/// "You have it", with the date it changed hands when [withDate].
String bookWhereabouts(Book book, String? me, {bool withDate = false}) {
  final l10n = currentL10n;
  final holder = book.holder;
  if (holder == null) {
    return l10n.bookAvailableAt(book.owner?.displayName ?? l10n.someone);
  }
  final since = book.heldSince;
  final date = withDate && since != null ? _date(since) : null;
  if (holder.id == me) {
    return date == null ? l10n.bookWithYou : l10n.bookWithYouSince(date);
  }
  return date == null
      ? l10n.bookHeldBy(holder.displayName)
      : l10n.bookHeldBySince(holder.displayName, date);
}

String _date(DateTime at) {
  final local = at.toLocal();
  return local.year == DateTime.now().year
      ? DateFormat.MMMd().format(local)
      : DateFormat.yMMMd().format(local);
}
