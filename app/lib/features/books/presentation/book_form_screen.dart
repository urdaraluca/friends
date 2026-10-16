import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_error_messages.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/forms/field_errors.dart';
import 'package:friends/core/forms/validators.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/core/widgets/form_widgets.dart';
import 'package:friends/features/books/data/books_providers.dart';
import 'package:friends/features/books/data/cover_picker.dart';
import 'package:friends/features/books/domain/book_genres.dart';
import 'package:friends/features/books/domain/book_languages.dart';
import 'package:friends/features/books/domain/isbn.dart';
import 'package:friends/features/books/presentation/isbn_scanner_screen.dart';
import 'package:friends/features/books/presentation/widgets/book_cover.dart';
import 'package:friends/features/groups/data/group_providers.dart';
import 'package:friends/features/groups/presentation/widgets/group_themed.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Adds a book to the group's shelf (`/groups/:groupId/books/new`) or edits
/// one (`/groups/:groupId/books/:bookId/edit`, its owner, whoever added it,
/// or an admin).
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

/// What happens to the cover when the form is saved.
sealed class _CoverChange {
  const new();
}

/// Leave it as it is (none on a new book).
class _KeepCover extends _CoverChange {
  const new();
}

/// Upload a photo the member took or picked.
class _PhotoCover extends _CoverChange {
  const new(this.bytes);
  final Uint8List bytes;
}

/// Use the cover the ISBN lookup found (shown from [url] until saved).
class _IsbnCover extends _CoverChange {
  const new(this.url);
  final String url;
}

/// Remove the book's cover.
class _RemoveCover extends _CoverChange {
  const new();
}

/// A book's cover, ISBN (scan or type it to fill the rest), title, author,
/// genre, language, description, owner and holder: `BookCreate` /
/// `BookWrite`, plus the cover and handover calls.
class BookForm extends ConsumerStatefulWidget {
  const new({required this.groupId, this.book, super.key});

  final String groupId;

  /// The book to edit, or null to add one.
  final Book? book;

  @override
  ConsumerState<BookForm> createState() => _BookFormState();
}

class _BookFormState extends ConsumerState<BookForm> with ServerErrorsMixin {
  static const _fields = {
    'title',
    'author',
    'description',
    'isbn',
    'genre',
    'language',
    'owner_id',
    'holder_id',
  };

  static Map<String, String> get _messages => {
    ErrorCodes.limitReached: currentL10n.bookLimitReached,
  };

  /// The language dropdown's "Other…" entry.
  static const _otherLanguage = '*';

  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.book?.title);
  late final _author = TextEditingController(text: widget.book?.author);
  late final _description = TextEditingController(
    text: widget.book?.description,
  );
  late final _isbn = TextEditingController(text: widget.book?.isbn);
  late BookGenre? _genre = switch (widget.book?.genre) {
    BookGenre.$unknown => null,
    final genre => genre,
  };
  late String? _language = widget.book?.language;

  /// Null: me (a new book's default).
  late String? _ownerId = widget.book?.owner?.id;

  /// Null: with its owner.
  late String? _holderId = widget.book?.holder?.id;
  _CoverChange _cover = const _KeepCover();
  bool _saving = false;
  bool _lookingUp = false;

  /// Bumped when a lookup fills the dropdowns, so they show the new values.
  int _filled = 0;

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _description.dispose();
    _isbn.dispose();
    super.dispose();
  }

  static String? _optional(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  // --- the ISBN ------------------------------------------------------------

  Future<void> _scan() async {
    final isbn = await scanIsbn(context);
    if (isbn == null || !mounted) return;
    _isbn.text = isbn;
    clearServerError('isbn');
    await _lookUp();
  }

  Future<void> _lookUp() async {
    final isbn = normalizeIsbn(_isbn.text);
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    // A new answer replaces the last one at once.
    void say(String message) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    if (isbn == null) {
      say(l10n.invalidIsbnError);
      return;
    }
    setState(() => _lookingUp = true);
    final IsbnLookup found;
    try {
      found = await ref.read(booksControllerProvider.notifier).lookUpIsbn(isbn);
    } on ApiException catch (error) {
      final notFound =
          error is ProblemException && error.code == ErrorCodes.notFound;
      say(notFound ? l10n.isbnNotFound : friendlyErrorMessage(error));
      return;
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
    if (mounted) await _fill(found);
  }

  /// Puts what the lookup [found] into the form. Fields the member already
  /// typed are only replaced if they say so.
  Future<void> _fill(IsbnLookup found) async {
    final typed =
        (_optional(_title) != null && _title.text.trim() != found.title) ||
        (_optional(_author) != null &&
            found.author != null &&
            _author.text.trim() != found.author) ||
        (_optional(_description) != null && found.description != null);
    final replace =
        !typed ||
        await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(context.l10n.useFoundDetailsTitle),
                content: Text(context.l10n.useFoundDetailsMessage(found.title)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(context.l10n.keepMine),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(context.l10n.useFoundDetails),
                  ),
                ],
              ),
            ) ==
            true;
    if (!mounted) return;
    void put(TextEditingController controller, String? value) {
      if (value != null && (replace || _optional(controller) == null)) {
        controller.text = value;
      }
    }

    setState(() {
      _isbn.text = found.isbn;
      put(_title, found.title);
      put(_author, found.author);
      put(_description, found.description);
      final genre = found.genre;
      if (genre != null && genre != BookGenre.$unknown) {
        if (replace || _genre == null) _genre = genre;
      }
      if (found.language case final language?) {
        if (replace || _language == null) _language = language;
      }
      final hasCover =
          _cover is _PhotoCover ||
          (widget.book?.coverUpdatedAt != null && _cover is! _RemoveCover);
      if (found.coverUrl case final url? when !hasCover || replace) {
        _cover = _IsbnCover(url);
      }
      _filled++;
    });
    ['title', 'author', 'description', 'isbn'].forEach(clearServerError);
  }

  // --- the cover -----------------------------------------------------------

  Future<void> _pickCover(CoverSource source) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      final bytes = await ref.read(coverPickerProvider)(source);
      if (bytes == null || !mounted) return;
      setState(() => _cover = _PhotoCover(bytes));
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(l10n.cameraUnavailable)));
    }
  }

  bool get _showsCover => switch (_cover) {
    _PhotoCover() || _IsbnCover() => true,
    _RemoveCover() => false,
    _KeepCover() => widget.book?.coverUpdatedAt != null,
  };

  Widget _coverImage() {
    const width = 96.0;
    final book = widget.book;
    return switch (_cover) {
      _PhotoCover(:final bytes) => CoverPreview(width: width, bytes: bytes),
      _IsbnCover(:final url) => CoverPreview(width: width, url: url),
      _RemoveCover() => const CoverPreview(width: width),
      _KeepCover() =>
        book == null
            ? const CoverPreview(width: width)
            : BookCover(book: book, width: width),
    };
  }

  // --- saving --------------------------------------------------------------

  Future<void> _save() async {
    clearFormError();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final controller = ref.read(booksControllerProvider.notifier);
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final isbn = normalizeIsbn(_isbn.text);
    try {
      final book = widget.book;
      var saved = book == null
          ? await controller.create(
              widget.groupId,
              BookCreate(
                title: _title.text.trim(),
                author: _optional(_author),
                description: _optional(_description),
                isbn: isbn,
                genre: _genre,
                language: _language,
                ownerId: _ownerId,
                holderId: _holderId,
              ),
            )
          // The owner changes last: a previous owner may not edit it after.
          : await controller.update(book, _write(isbn, ownerId: null));
      final coverSaved = await _saveCover(controller, saved);
      if (coverSaved != null) saved = coverSaved;
      if (book != null) {
        if (_holderId != book.holder?.id && saved.canHandOver) {
          saved = await controller.handOver(saved, _holderId);
        }
        final ownerId = _ownerId;
        if (ownerId != null && ownerId != book.owner?.id) {
          saved = await controller.update(
            saved,
            _write(isbn, ownerId: ownerId),
          );
        }
      }
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

  BookWrite _write(String? isbn, {required String? ownerId}) => BookWrite(
    title: _title.text.trim(),
    author: _optional(_author),
    description: _optional(_description),
    isbn: isbn,
    genre: _genre,
    language: _language,
    ownerId: ownerId,
  );

  /// Applies the cover change to [book]; the updated book, or null when
  /// nothing changed. A cover that fails doesn't fail the book: it says so
  /// and moves on.
  Future<Book?> _saveCover(BooksController controller, Book book) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      return switch (_cover) {
        _KeepCover() => null,
        _PhotoCover(:final bytes) => await controller.uploadCover(book, bytes),
        _IsbnCover() =>
          book.isbn == null ? null : await controller.useIsbnCover(book),
        _RemoveCover() => await controller.deleteCover(book),
      };
    } on ApiException catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.coverNotSaved(friendlyErrorMessage(error))),
        ),
      );
      return null;
    }
  }

  // --- the language --------------------------------------------------------

  Future<void> _pickOtherLanguage() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.l10n.bookLanguageLabel),
        children: [
          for (final MapEntry(key: code, value: name)
              in (bookLanguageNames.entries.toList()
                ..sort((a, b) => a.value.compareTo(b.value))))
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(code),
              child: Text(name),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _language = picked;
      _filled++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final book = widget.book;
    final me = ref.watch(currentUserIdProvider);
    final members = ref.watch(membersProvider(widget.groupId)).value ?? [];
    final ownerId = _ownerId ?? me;
    final memberIds = {for (final m in members) m.user.id};
    final canHandOver = book == null || book.canHandOver;
    final languages = [
      ...commonBookLanguages,
      if (_language case final language?
          when !commonBookLanguages.contains(language))
        language,
    ];
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (formError case final message?) ...[
            FormMessageBanner(message: message),
            const SizedBox(height: 16),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _coverImage(),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.coverLabel,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _saving
                              ? null
                              : () => unawaited(_pickCover(CoverSource.camera)),
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: Text(l10n.takePhoto),
                        ),
                        OutlinedButton.icon(
                          onPressed: _saving
                              ? null
                              : () =>
                                    unawaited(_pickCover(CoverSource.gallery)),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: Text(l10n.choosePhoto),
                        ),
                        if (_showsCover)
                          TextButton.icon(
                            onPressed: _saving
                                ? null
                                : () => setState(
                                    () => _cover = book?.coverUpdatedAt == null
                                        ? const _KeepCover()
                                        : const _RemoveCover(),
                                  ),
                            icon: const Icon(Icons.delete_outline),
                            label: Text(l10n.removeCover),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: _saving || _lookingUp ? null : () => unawaited(_scan()),
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(l10n.scanIsbn),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _isbn,
            decoration: InputDecoration(
              labelText: l10n.isbnLabel,
              helperText: l10n.isbnHelp,
              suffixIcon: _lookingUp
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      tooltip: l10n.lookUpIsbn,
                      icon: const Icon(Icons.search),
                      onPressed: _saving ? null : () => unawaited(_lookUp()),
                    ),
            ),
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.search,
            onFieldSubmitted: (_) => unawaited(_lookUp()),
            validator: (value) =>
                (value ?? '').trim().isEmpty || normalizeIsbn(value!) != null
                ? null
                : l10n.invalidIsbnError,
            forceErrorText: serverError('isbn'),
            onChanged: (_) => clearServerError('isbn'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _title,
            decoration: InputDecoration(labelText: l10n.titleLabel),
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            validator: Validators.required(l10n.enterTitle, max: 200),
            forceErrorText: serverError('title'),
            onChanged: (_) => clearServerError('title'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _author,
            decoration: InputDecoration(
              labelText: l10n.authorLabel,
              helperText: l10n.optional,
            ),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            validator: Validators.optional(max: 120),
            forceErrorText: serverError('author'),
            onChanged: (_) => clearServerError('author'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<BookGenre?>(
            key: ValueKey(('genre', _filled)),
            initialValue: _genre,
            decoration: InputDecoration(
              labelText: l10n.genreLabel,
              errorText: serverError('genre'),
            ),
            items: [
              DropdownMenuItem(child: Text(l10n.notSet)),
              for (final genre in bookGenres)
                DropdownMenuItem(value: genre, child: Text(genre.label)),
            ],
            onChanged: (value) {
              clearServerError('genre');
              setState(() => _genre = value);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            key: ValueKey(('language', _filled)),
            initialValue: _language,
            decoration: InputDecoration(
              labelText: l10n.bookLanguageLabel,
              errorText: serverError('language'),
            ),
            items: [
              DropdownMenuItem(child: Text(l10n.notSet)),
              for (final code in languages)
                DropdownMenuItem(
                  value: code,
                  child: Text(bookLanguageName(code)),
                ),
              DropdownMenuItem(
                value: _otherLanguage,
                child: Text(l10n.otherLanguage),
              ),
            ],
            onChanged: (value) {
              clearServerError('language');
              if (value == _otherLanguage) {
                // Show the current choice until one is picked.
                setState(() => _filled++);
                unawaited(_pickOtherLanguage());
                return;
              }
              setState(() => _language = value);
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _description,
            decoration: InputDecoration(
              labelText: l10n.descriptionLabel,
              helperText: l10n.optional,
            ),
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            validator: Validators.optional(max: 5000),
            forceErrorText: serverError('description'),
            onChanged: (_) => clearServerError('description'),
          ),
          if (members.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const ValueKey('owner'),
              initialValue: memberIds.contains(ownerId) ? ownerId : null,
              decoration: InputDecoration(
                labelText: l10n.bookOwnerLabel,
                errorText: serverError('owner_id'),
              ),
              items: [
                for (final member in members)
                  DropdownMenuItem(
                    value: member.user.id,
                    child: Text(
                      member.user.id == me
                          ? l10n.memberYou(member.user.displayName)
                          : member.user.displayName,
                    ),
                  ),
              ],
              onChanged: (value) {
                clearServerError('owner_id');
                setState(() {
                  _ownerId = value;
                  // The owner having it means it is with its owner.
                  if (_holderId == value) _holderId = null;
                });
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: ValueKey(('holder', ownerId)),
              initialValue: memberIds.contains(_holderId) ? _holderId : null,
              decoration: InputDecoration(
                labelText: l10n.whoHasItLabel,
                helperText: canHandOver ? null : l10n.onlyOwnerOrHolderLends,
                errorText: serverError('holder_id'),
              ),
              items: [
                DropdownMenuItem(child: Text(l10n.withTheOwner)),
                for (final member in members)
                  if (member.user.id != ownerId)
                    DropdownMenuItem(
                      value: member.user.id,
                      child: Text(
                        member.user.id == me
                            ? l10n.memberYou(member.user.displayName)
                            : member.user.displayName,
                      ),
                    ),
              ],
              onChanged: canHandOver
                  ? (value) {
                      clearServerError('holder_id');
                      setState(() => _holderId = value);
                    }
                  : null,
            ),
          ],
          const SizedBox(height: 24),
          SubmitButton(
            label: book == null ? l10n.addBook : l10n.save,
            busy: _saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
