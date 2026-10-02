import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/api_providers.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'books_providers.g.dart';

/// A group's book archive, by title (`GET /groups/{id}/books`, contract
/// section 17). The whole archive comes at once, so the list and a book's
/// page both read it.
///
/// Mutations put the server's response in place ([put], [remove]).
@riverpod
class Books extends _$Books {
  @override
  Future<List<Book>> build(String groupId) {
    ref.watch(currentUserIdProvider);
    final client = ref.watch(booksClientProvider);
    return apiCall(() => client.listBooks(groupId: groupId));
  }

  /// Replaces the book with [book]'s ID, or adds [book] in title order.
  void put(Book book) {
    final books = state.value;
    if (books == null) return;
    if (books.any((b) => b.id == book.id)) {
      state = AsyncData([
        for (final b in books)
          if (b.id == book.id) book else b,
      ]);
      return;
    }
    final title = book.title.toLowerCase();
    final at = books.indexWhere(
      (b) => b.title.toLowerCase().compareTo(title) > 0,
    );
    state = AsyncData([...books]..insert(at < 0 ? books.length : at, book));
  }

  /// Drops the book with [bookId].
  void remove(String bookId) {
    final books = state.value;
    if (books == null) return;
    state = AsyncData([
      for (final b in books)
        if (b.id != bookId) b,
    ]);
  }
}

/// Every book mutation (contract section 17.3). Each method throws
/// `ApiException`s; on success it puts the server's book into
/// [booksProvider].
@Riverpod(keepAlive: true)
class BooksController extends _$BooksController {
  @override
  void build() {}

  BooksClient get _client => ref.read(booksClientProvider);

  Future<Book> _apply(Future<Book> Function() call) async {
    final book = await apiCall(call);
    ref.read(booksProvider(book.groupId).notifier).put(book);
    return book;
  }

  /// `POST /groups/{id}/books`: I own it, and it is with me.
  Future<Book> create(String groupId, BookWrite body) =>
      _apply(() => _client.createBook(groupId: groupId, body: body));

  /// `PUT /books/{id}` (`can_edit`).
  Future<Book> update(Book book, BookWrite body) =>
      _apply(() => _client.updateBook(bookId: book.id, body: body));

  /// `DELETE /books/{id}` (`can_edit`).
  Future<void> delete(Book book) async {
    await apiCall(() => _client.deleteBook(bookId: book.id));
    ref.read(booksProvider(book.groupId).notifier).remove(book.id);
  }

  /// `PUT /books/{id}/queue`: I join the end of the queue.
  Future<Book> joinQueue(Book book) =>
      _apply(() => _client.joinBookQueue(bookId: book.id));

  /// `DELETE /books/{id}/queue`.
  Future<Book> leaveQueue(Book book) =>
      _apply(() => _client.leaveBookQueue(bookId: book.id));

  /// `POST /books/{id}/handover` (`can_hand_over`): [toUserId] has it now,
  /// or null: it is back with its owner.
  Future<Book> handOver(Book book, String? toUserId) => _apply(
    () => _client.handOverBook(
      bookId: book.id,
      body: Handover(toUserId: toUserId),
    ),
  );

  /// Reloads the group's books (e.g. after a 409).
  void refresh(String groupId) => ref.invalidate(booksProvider(groupId));
}
