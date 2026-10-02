import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/forms/field_errors.dart';
import 'package:friends/core/forms/validators.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/core/widgets/form_widgets.dart';
import 'package:friends/features/books/data/books_providers.dart';
import 'package:friends/features/groups/presentation/widgets/group_themed.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Adds a book to the group's shelf (`/groups/:groupId/books/new`) or edits
/// one (`/groups/:groupId/books/:bookId/edit`, its owner or an admin).
class BookFormScreen extends ConsumerWidget {
  /// The new-book form.
  const new create({required this.groupId, super.key}) : bookId = null;

  /// The edit form of [bookId].
  const new edit({
    required this.groupId,
    required String this.bookId,
    super.key,
  });

  final String groupId;

  /// The book to edit, or null to add one.
  final String? bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookId = this.bookId;
    final books = ref.watch(booksProvider(groupId));
    return GroupThemed(
      groupId: groupId,
      child: Scaffold(
        appBar: AppBar(
          // Opened directly (a deep link or a reload): nothing to pop.
          leading: context.canPop()
              ? null
              : IconButton(
                  tooltip: context.l10n.close,
                  icon: const Icon(Icons.close),
                  onPressed: () => context.go(
                    bookId == null
                        ? Routes.groupBooks(groupId)
                        : Routes.book(groupId, bookId),
                  ),
                ),
          title: Text(
            bookId == null ? context.l10n.newBook : context.l10n.editBook,
          ),
        ),
        body: bookId == null
            ? FormPage(maxWidth: 560, child: BookForm(groupId: groupId))
            : AsyncValueView(
                value: books,
                onRetry: () => ref.invalidate(booksProvider(groupId)),
                data: (books) =>
                    switch (books.where((b) => b.id == bookId).firstOrNull) {
                      final book? => FormPage(
                        maxWidth: 560,
                        child: BookForm(
                          key: ValueKey(book.id),
                          groupId: groupId,
                          book: book,
                        ),
                      ),
                      null => Center(child: Text(context.l10n.bookNotFound)),
                    },
              ),
      ),
    );
  }
}

/// Title (1..200), author (≤120) and description (≤5000): `BookWrite`.
class BookForm extends ConsumerStatefulWidget {
  const new({required this.groupId, this.book, super.key});

  final String groupId;

  /// The book to edit, or null to add one.
  final Book? book;

  @override
  ConsumerState<BookForm> createState() => _BookFormState();
}

class _BookFormState extends ConsumerState<BookForm> with ServerErrorsMixin {
  static const _fields = {'title', 'author', 'description'};

  static Map<String, String> get _messages => {
    ErrorCodes.limitReached: currentL10n.bookLimitReached,
  };

  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.book?.title);
  late final _author = TextEditingController(text: widget.book?.author);
  late final _description = TextEditingController(
    text: widget.book?.description,
  );
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _description.dispose();
    super.dispose();
  }

  static String? _optional(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _save() async {
    clearFormError();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final controller = ref.read(booksControllerProvider.notifier);
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final body = BookWrite(
      title: _title.text.trim(),
      author: _optional(_author),
      description: _optional(_description),
    );
    try {
      final book = widget.book;
      final saved = book == null
          ? await controller.create(widget.groupId, body)
          : await controller.update(book, body);
      messenger.showSnackBar(SnackBar(content: Text(l10n.bookSaved)));
      if (book == null) {
        unawaited(
          router.pushReplacement(Routes.book(widget.groupId, saved.id)),
        );
      } else if (router.canPop()) {
        router.pop();
      } else {
        router.go(Routes.book(widget.groupId, saved.id));
      }
    } on ApiException catch (e) {
      if (mounted) showServerError(e, fields: _fields, messages: _messages);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (formError case final message?) ...[
            FormMessageBanner(message: message),
            const SizedBox(height: 16),
          ],
          TextFormField(
            controller: _title,
            decoration: InputDecoration(labelText: context.l10n.titleLabel),
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            validator: Validators.required(context.l10n.enterTitle, max: 200),
            forceErrorText: serverError('title'),
            onChanged: (_) => clearServerError('title'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _author,
            decoration: InputDecoration(
              labelText: context.l10n.authorLabel,
              helperText: context.l10n.optional,
            ),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            validator: Validators.optional(max: 120),
            forceErrorText: serverError('author'),
            onChanged: (_) => clearServerError('author'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _description,
            decoration: InputDecoration(
              labelText: context.l10n.descriptionLabel,
              helperText: context.l10n.optional,
            ),
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            validator: Validators.optional(max: 5000),
            forceErrorText: serverError('description'),
            onChanged: (_) => clearServerError('description'),
          ),
          const SizedBox(height: 24),
          SubmitButton(
            label: widget.book == null
                ? context.l10n.addBook
                : context.l10n.save,
            busy: _saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
