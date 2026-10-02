// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/book.dart';
import '../models/book_write.dart';
import '../models/handover.dart';

part 'books_client.g.dart';

@RestApi()
abstract class BooksClient {
  factory BooksClient(Dio dio, {String? baseUrl}) = _BooksClient;

  /// List Books.
  ///
  /// Every book in the group, by title.
  @GET('/api/v1/groups/{group_id}/books')
  Future<List<Book>> listBooks({
    @Path('group_id') required String groupId,
  });

  /// Create Book.
  ///
  /// Any member. The caller owns the book, and it is with them.
  @POST('/api/v1/groups/{group_id}/books')
  Future<Book> createBook({
    @Path('group_id') required String groupId,
    @Body() required BookWrite body,
  });

  /// Get Book
  @GET('/api/v1/books/{book_id}')
  Future<Book> getBook({
    @Path('book_id') required String bookId,
  });

  /// Update Book.
  ///
  /// The owner or an admin.
  @PUT('/api/v1/books/{book_id}')
  Future<Book> updateBook({
    @Path('book_id') required String bookId,
    @Body() required BookWrite body,
  });

  /// Delete Book.
  ///
  /// The owner or an admin.
  @DELETE('/api/v1/books/{book_id}')
  Future<void> deleteBook({
    @Path('book_id') required String bookId,
  });

  /// Join Book Queue.
  ///
  /// Joins the end of the queue (idempotent). Not for the owner or whoever has the book.
  @PUT('/api/v1/books/{book_id}/queue')
  Future<Book> joinBookQueue({
    @Path('book_id') required String bookId,
  });

  /// Leave Book Queue.
  ///
  /// Leaves the queue (idempotent).
  @DELETE('/api/v1/books/{book_id}/queue')
  Future<Book> leaveBookQueue({
    @Path('book_id') required String bookId,
  });

  /// Hand Over Book.
  ///
  /// The owner, whoever has the book or an admin.
  ///
  /// Gives it to a member, who leaves the queue.
  /// A null ``to_user_id`` gives it back to its owner.
  @POST('/api/v1/books/{book_id}/handover')
  Future<Book> handOverBook({
    @Path('book_id') required String bookId,
    @Body() required Handover body,
  });
}
