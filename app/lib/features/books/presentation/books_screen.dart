import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/features/books/data/books_providers.dart';
import 'package:friends/features/books/domain/book_genres.dart';
import 'package:friends/features/books/domain/book_languages.dart';
import 'package:friends/features/books/domain/book_status.dart';
import 'package:friends/features/books/presentation/widgets/book_cover.dart';
import 'package:friends/features/books/presentation/widgets/star_rating.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// The Books tab (`/groups/:groupId/books`): the group's shared shelf, with
/// a search, quick filters, genre and language filters, a sort, and who has
/// each book.
class BooksScreen extends ConsumerStatefulWidget {
  const new({required this.groupId, super.key});

  final String groupId;

  @override
  ConsumerState<BooksScreen> createState() => _BooksScreenState();
}

class _BooksScreenState extends ConsumerState<BooksScreen> {
  final _search = TextEditingController();
  BookFilter _filter = BookFilter.all;
  BookGenre? _genre;
  String? _language;
  BookSort _sort = BookSort.title;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// The sort, and the genres and languages the shelf has, as menus.
  Widget _shelfMenus(BuildContext context, List<Book> books) {
    final l10n = context.l10n;
    final genres = {for (final b in books) ?b.genre}
      ..remove(BookGenre.$unknown);
    final languages = {for (final b in books) ?b.language}.toList()
      ..sort((a, b) => bookLanguageName(a).compareTo(bookLanguageName(b)));
    final genre = _genre;
    final language = _language;
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _MenuChip<BookSort>(
            key: const ValueKey('sort-menu'),
            icon: Icons.sort,
            label: _sort.label,
            selected: _sort != BookSort.title,
            options: [for (final sort in BookSort.values) (sort, sort.label)],
            onSelected: (sort) => setState(() => _sort = sort),
          ),
          if (genres.isNotEmpty || genre != null)
            _MenuChip<String>(
              key: const ValueKey('genre-menu'),
              icon: Icons.category_outlined,
              label: genre?.label ?? l10n.allGenres,
              selected: genre != null,
              options: [
                ('', l10n.allGenres),
                for (final g in bookGenres)
                  if (genres.contains(g)) (g.json!, g.label),
              ],
              onSelected: (json) => setState(
                () => _genre = json.isEmpty ? null : BookGenre.fromJson(json),
              ),
            ),
          if (languages.isNotEmpty || language != null)
            _MenuChip<String>(
              key: const ValueKey('language-menu'),
              icon: Icons.translate,
              label: language == null
                  ? l10n.allLanguages
                  : bookLanguageName(language),
              selected: language != null,
              options: [
                ('', l10n.allLanguages),
                for (final code in languages) (code, bookLanguageName(code)),
              ],
              onSelected: (code) =>
                  setState(() => _language = code.isEmpty ? null : code),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groupId = widget.groupId;
    final books = ref.watch(booksProvider(groupId));
    final me = ref.watch(currentUserIdProvider);
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: context.l10n.booksSearchHint,
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: context.l10n.close,
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final filter in BookFilter.values)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(filter.label),
                      selected: _filter == filter,
                      onSelected: (_) => setState(() => _filter = filter),
                    ),
                  ),
              ],
            ),
          ),
          _shelfMenus(context, books.value ?? const []),
          Expanded(
            child: AsyncValueView(
              value: books,
              onRetry: () => ref.invalidate(booksProvider(groupId)),
              data: (books) {
                final shown = _sort.apply([
                  for (final book in books)
                    if (_filter.matches(book, me) &&
                        (_genre == null || book.genre == _genre) &&
                        (_language == null || book.language == _language) &&
                        bookMatchesQuery(book, _search.text))
                      book,
                ]);
                return RefreshIndicator(
                  onRefresh: () =>
                      settled([ref.refresh(booksProvider(groupId).future)]),
                  child: shown.isEmpty
                      ? _EmptyShelf(filtered: books.isNotEmpty)
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(top: 4, bottom: 88),
                          itemCount: shown.length,
                          itemBuilder: (context, index) => BookCard(
                            book: shown[index],
                            me: me,
                            onTap: () => unawaited(
                              context.push(
                                Routes.book(groupId, shown[index].id),
                              ),
                            ),
                          ),
                        ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-book',
        onPressed: () => unawaited(context.push(Routes.newBook(groupId))),
        icon: const Icon(Icons.add),
        label: Text(context.l10n.addBook),
      ),
    );
  }
}

/// A book in the list: its cover, title, author, rating, who has it, and how
/// many wait.
class BookCard extends StatelessWidget {
  const new({
    required this.book,
    required this.me,
    required this.onTap,
    super.key,
  });

  final Book book;
  final String? me;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final place = queuePosition(book, me);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        onTap: onTap,
        leading: BookCover(book: book, width: 40),
        title: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text([?book.author, bookWhereabouts(book, me)].join('\n')),
            if (book.ratingCount > 0)
              RatingSummary(
                average: book.ratingAverage,
                count: book.ratingCount,
                style: textTheme.bodySmall,
              ),
          ],
        ),
        isThreeLine: book.author != null || book.ratingCount > 0,
        trailing: book.queue.isEmpty
            ? null
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    context.l10n.bookWaitingCount(book.queue.length),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  if (place != null)
                    Text(
                      '#$place',
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(color: colors.primary),
                    ),
                ],
              ),
      ),
    );
  }
}

class _EmptyShelf extends StatelessWidget {
  const new({required this.filtered});

  /// There are books, just none matching the search and filter.
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        Icon(
          Icons.auto_stories_outlined,
          size: 56,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(height: 16),
        if (filtered)
          Text(
            context.l10n.noBooksMatch,
            textAlign: TextAlign.center,
            style: textTheme.titleMedium,
          )
        else ...[
          Text(
            context.l10n.noBooksYet,
            textAlign: TextAlign.center,
            style: textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.noBooksHelp,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium,
          ),
        ],
      ],
    );
  }
}

/// A chip that opens a menu of [options] (value, label).
class _MenuChip<T> extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    required this.selected,
    required this.options,
    required this.onSelected,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final List<(T, String)> options;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: PopupMenuButton<T>(
        tooltip: label,
        onSelected: onSelected,
        itemBuilder: (context) => [
          for (final (value, text) in options)
            PopupMenuItem(value: value, child: Text(text)),
        ],
        child: Chip(
          avatar: Icon(icon, size: 18),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              const Icon(Icons.arrow_drop_down, size: 18),
            ],
          ),
          backgroundColor: selected ? colors.secondaryContainer : null,
        ),
      ),
    );
  }
}
