import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/features/books/data/books_providers.dart';
import 'package:friends/features/books/domain/book_status.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// The Books tab (`/groups/:groupId/books`): the group's shared shelf, with
/// a search, quick filters, and who has each book.
class BooksScreen extends ConsumerStatefulWidget {
  const new({required this.groupId, super.key});

  final String groupId;

  @override
  ConsumerState<BooksScreen> createState() => _BooksScreenState();
}

class _BooksScreenState extends ConsumerState<BooksScreen> {
  final _search = TextEditingController();
  BookFilter _filter = BookFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
          Expanded(
            child: AsyncValueView(
              value: books,
              onRetry: () => ref.invalidate(booksProvider(groupId)),
              data: (books) {
                final shown = [
                  for (final book in books)
                    if (_filter.matches(book, me) &&
                        bookMatchesQuery(book, _search.text))
                      book,
                ];
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

/// A book in the list: title, author, who has it, and how many wait.
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
    final available = book.holder == null;
    final place = queuePosition(book, me);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: available
              ? colors.secondaryContainer
              : colors.surfaceContainerHighest,
          foregroundColor: available
              ? colors.onSecondaryContainer
              : colors.onSurfaceVariant,
          child: Icon(available ? Icons.menu_book : Icons.outbound_outlined),
        ),
        title: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text([?book.author, bookWhereabouts(book, me)].join('\n')),
        isThreeLine: book.author != null,
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
