import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_error_messages.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/core/widgets/confirm_dialog.dart';
import 'package:friends/core/widgets/user_avatar.dart';
import 'package:friends/features/books/data/books_providers.dart';
import 'package:friends/features/books/domain/book_status.dart';
import 'package:friends/features/groups/data/group_providers.dart';
import 'package:friends/features/groups/presentation/widgets/group_themed.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// A book (`/groups/:groupId/books/:bookId`): who owns it, who has it, the
/// waiting list, and the buttons to pass it on.
class BookDetailScreen extends ConsumerWidget {
  const new({required this.groupId, required this.bookId, super.key});

  final String groupId;
  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(booksProvider(groupId));
    final book = books.value?.where((b) => b.id == bookId).firstOrNull;
    return GroupThemed(
      groupId: groupId,
      child: Scaffold(
        appBar: AppBar(
          title: Text(book?.title ?? context.l10n.tabBooks),
          actions: [
            if (book != null && book.canEdit)
              _BookMenu(groupId: groupId, book: book),
          ],
        ),
        body: AsyncValueView(
          value: books,
          onRetry: () => ref.invalidate(booksProvider(groupId)),
          data: (_) => book == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      context.l10n.bookNotFound,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () =>
                      settled([ref.refresh(booksProvider(groupId).future)]),
                  child: _BookBody(groupId: groupId, book: book),
                ),
        ),
      ),
    );
  }
}

class _BookMenu extends ConsumerWidget {
  const new({required this.groupId, required this.book});

  final String groupId;
  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: context.l10n.more,
      onSelected: (action) => switch (action) {
        'edit' => unawaited(context.push(Routes.editBook(groupId, book.id))),
        'delete' => unawaited(_delete(context, ref)),
        _ => null,
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'edit',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.edit_outlined),
            title: Text(context.l10n.edit),
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_outline),
            title: Text(context.l10n.delete),
          ),
        ),
      ],
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.deleteBookTitle,
      message: l10n.deleteBookMessage,
      confirmLabel: l10n.delete,
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ref.read(booksControllerProvider.notifier).delete(book);
      router.go(Routes.groupBooks(groupId));
      messenger.showSnackBar(SnackBar(content: Text(l10n.bookDeleted)));
    } on ApiException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    }
  }
}

class _BookBody extends ConsumerStatefulWidget {
  const new({required this.groupId, required this.book});

  final String groupId;
  final Book book;

  @override
  ConsumerState<_BookBody> createState() => _BookBodyState();
}

class _BookBodyState extends ConsumerState<_BookBody> {
  bool _busy = false;

  BooksController get _controller => ref.read(booksControllerProvider.notifier);

  /// Runs [action], with the buttons off meanwhile; [done] is the snackbar
  /// text on success.
  Future<void> _run(Future<Object?> Function() action, {String? done}) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      if (done != null) {
        messenger.showSnackBar(SnackBar(content: Text(done)));
      }
    } on ApiException catch (error) {
      // Someone else changed the book meanwhile: show its current state.
      if (error is ProblemException &&
          (error.code == ErrorCodes.ownBook ||
              error.code == ErrorCodes.alreadyHolding ||
              error.code == ErrorCodes.forbidden)) {
        _controller.refresh(widget.groupId);
      }
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _lendToSomeoneElse() async {
    final book = widget.book;
    final members = await ref.read(membersProvider(widget.groupId).future);
    if (!mounted) return;
    final candidates = [
      for (final member in members)
        if (member.user.id != book.owner?.id &&
            member.user.id != book.holder?.id)
          member.user,
    ];
    final picked = await showDialog<UserPublic>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.l10n.whoHasItNow),
        children: [
          for (final user in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(user),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: UserAvatar(user: user),
                title: Text(user.displayName),
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    await _run(
      () => _controller.handOver(book, picked.id),
      done: context.l10n.nowHasIt(picked.displayName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final me = ref.watch(currentUserIdProvider);
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final owner = book.owner;
    final holder = book.holder;
    final next = book.queue.firstOrNull?.user;
    final place = queuePosition(book, me);
    final canQueue = me != owner?.id && me != holder?.id;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text(book.title, style: textTheme.headlineSmall),
        if (book.author case final author?) ...[
          const SizedBox(height: 4),
          Text(
            author,
            style: textTheme.titleMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
        if (book.description case final description?) ...[
          const SizedBox(height: 12),
          Text(description, style: textTheme.bodyLarge),
        ],
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.whereItIs, style: textTheme.titleMedium),
                if (owner != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: UserAvatar(user: owner),
                    title: Text(owner.displayName),
                    subtitle: Text(l10n.bookOwnerLabel),
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: holder == null
                      ? CircleAvatar(
                          backgroundColor: colors.secondaryContainer,
                          foregroundColor: colors.onSecondaryContainer,
                          child: const Icon(Icons.menu_book),
                        )
                      : UserAvatar(user: holder),
                  title: Text(bookWhereabouts(book, me, withDate: true)),
                ),
                if (book.canHandOver) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (next != null)
                        FilledButton.icon(
                          onPressed: _busy
                              ? null
                              : () => unawaited(
                                  _run(
                                    () => _controller.handOver(book, next.id),
                                    done: l10n.nowHasIt(next.displayName),
                                  ),
                                ),
                          icon: const Icon(Icons.outbound_outlined),
                          label: Text(l10n.lendTo(next.displayName)),
                        ),
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => unawaited(_lendToSomeoneElse()),
                        child: Text(
                          next == null
                              ? l10n.whoHasItNow
                              : l10n.lendToSomeoneElse,
                        ),
                      ),
                      if (holder != null && owner != null)
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => unawaited(
                                  _run(
                                    () => _controller.handOver(book, null),
                                    done: l10n.backWithOwner(owner.displayName),
                                  ),
                                ),
                          icon: const Icon(Icons.keyboard_return),
                          label: Text(l10n.backWithOwner(owner.displayName)),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.waitingList, style: textTheme.titleMedium),
                const SizedBox(height: 4),
                if (book.queue.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(l10n.nobodyWaiting),
                  )
                else
                  for (final (index, entry) in book.queue.indexed)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: UserAvatar(user: entry.user),
                      title: Text('${index + 1}. ${entry.user.displayName}'),
                      subtitle: Text(
                        DateFormat.MMMd().format(entry.joinedAt.toLocal()),
                      ),
                    ),
                if (place != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      l10n.yourQueuePlace(place),
                      style: textTheme.labelLarge?.copyWith(
                        color: colors.primary,
                      ),
                    ),
                  ),
                if (canQueue)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: book.inMyQueue
                        ? OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => unawaited(
                                    _run(() => _controller.leaveQueue(book)),
                                  ),
                            child: Text(l10n.leaveWaitingList),
                          )
                        : FilledButton.tonal(
                            onPressed: _busy
                                ? null
                                : () => unawaited(
                                    _run(() => _controller.joinQueue(book)),
                                  ),
                            child: Text(l10n.joinWaitingList),
                          ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
