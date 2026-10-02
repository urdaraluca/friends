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

/// Whether [book]'s title or author contains [query] (case-insensitive);
/// a blank query matches everything.
bool bookMatchesQuery(Book book, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return book.title.toLowerCase().contains(q) ||
      (book.author?.toLowerCase().contains(q) ?? false);
}

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
