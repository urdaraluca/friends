// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/book.dart';
import '../models/book_create.dart';
import '../models/book_write.dart';
import '../models/handover.dart';
import '../models/isbn_lookup.dart';
import '../models/rating_write.dart';

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
  /// Any member. The book is theirs and with them, unless the body names other members.
  @POST('/api/v1/groups/{group_id}/books')
  Future<Book> createBook({
    @Path('group_id') required String groupId,
    @Body() required BookCreate body,
  });

  /// Look Up Isbn.
  ///
  /// What the book catalogues know about an ISBN-10 or ISBN-13.
  @GET('/api/v1/books/isbn/{isbn}')
  Future<IsbnLookup> lookUpIsbn({
    @Path('isbn') required String isbn,
  });

  /// Get Book
  @GET('/api/v1/books/{book_id}')
  Future<Book> getBook({
    @Path('book_id') required String bookId,
  });

  /// Update Book.
  ///
  /// The owner, whoever added it or an admin.
  @PUT('/api/v1/books/{book_id}')
  Future<Book> updateBook({
    @Path('book_id') required String bookId,
    @Body() required BookWrite body,
  });

  /// Delete Book.
  ///
  /// The owner, whoever added it or an admin.
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

  /// Get Book Cover.
  ///
  /// The book's cover image.
  @GET('/api/v1/books/{book_id}/cover')
  @DioResponseType(ResponseType.stream)
  Stream<String> getBookCover({
    @Path('book_id') required String bookId,
  });

  /// Upload Book Cover.
  ///
  /// The owner, whoever added it or an admin. Replaces the cover.
  ///
  /// [file] - A JPEG, PNG or WebP image, up to 2 MB.
  @MultiPart()
  @PUT('/api/v1/books/{book_id}/cover')
  Future<Book> uploadBookCover({
    @Path('book_id') required String bookId,
    @Part(name: 'file') required MultipartFile file,
  });

  /// Delete Book Cover.
  ///
  /// The owner, whoever added it or an admin. Removes the cover (idempotent).
  @DELETE('/api/v1/books/{book_id}/cover')
  Future<Book> deleteBookCover({
    @Path('book_id') required String bookId,
  });

  /// Use Isbn Cover.
  ///
  /// The owner, whoever added it or an admin. The cover the book catalogues have for its ISBN.
  @POST('/api/v1/books/{book_id}/cover/isbn')
  Future<Book> useIsbnCover({
    @Path('book_id') required String bookId,
  });

  /// Rate Book.
  ///
  /// Any member. Sets the caller's stars, 1 to 5.
  @PUT('/api/v1/books/{book_id}/rating')
  Future<Book> rateBook({
    @Path('book_id') required String bookId,
    @Body() required RatingWrite body,
  });

  /// Unrate Book.
  ///
  /// Any member. Removes the caller's stars (idempotent).
  @DELETE('/api/v1/books/{book_id}/rating')
  Future<Book> unrateBook({
    @Path('book_id') required String bookId,
  });
}
