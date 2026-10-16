import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/features/books/data/cover_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_auth_controller.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/test_backend.dart';

/// Covers, the ISBN lookup, genre, language, owner, holder and ratings
/// (contract sections 17.3 and 17.5).
void main() {
  late TestBackend backend;

  final bea = userPublicJson(id: Ids.beaId, displayName: 'Bea');
  final cris = userPublicJson(id: Ids.crisId, displayName: 'Cris');
  const dune = '9780441172719';
  // A 1x1 PNG, so the preview can decode it.
  final photo = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGA'
    'WjR9awAAAABJRU5ErkJggg==',
  );

  setUp(() => backend = TestBackend());

  /// Signed in as Ana, in a book club whose shelf holds [books].
  Future<ProviderContainer> open(
    WidgetTester tester,
    String location, {
    List<Map<String, Object?>>? books,
    List<Object> overrides = const [],
  }) async {
    tester.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    backend
      ..stubGroup(
        group: groupJson(kind: 'book_club'),
        members: [
          memberJson(),
          memberJson(userId: Ids.beaId, displayName: 'Bea'),
          memberJson(userId: Ids.crisId, displayName: 'Cris'),
        ],
      )
      ..adapter.onJson('GET', ApiPaths.books(Ids.groupId), books ?? []);
    return await tester.pumpFriendsApp(
      overrides: [
        ...backend.overrides,
        authControllerProvider.overrideWith(
          () => FakeAuthController(signedIn()),
        ),
        ...overrides.cast(),
      ],
      location: location,
    );
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).first);
    await tester.tap(find.text(text).first);
    await tester.pumpAndSettle();
  }

  /// Opens the dropdown labelled [label] and picks [item].
  Future<void> pick(WidgetTester tester, String label, String item) async {
    final field = find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate(
        (widget) => widget is DropdownButtonFormField,
      ),
    );
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text(item).last);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester, String label) async {
    final button = find.widgetWithText(FilledButton, label);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  group('adding a book', () {
    testWidgets('looks up its ISBN, fills the form and keeps the cover', (
      tester,
    ) async {
      await open(tester, Routes.newBook(Ids.groupId));
      backend.adapter
        ..onJson('GET', ApiPaths.isbnLookup(dune), isbnLookupJson())
        ..onJson(
          'POST',
          ApiPaths.books(Ids.groupId),
          bookJson(isbn: dune, genre: 'sci_fi', language: 'en'),
          status: 201,
        )
        ..onJson(
          'POST',
          ApiPaths.bookIsbnCover(Ids.bookId),
          bookJson(
            isbn: dune,
            genre: 'sci_fi',
            language: 'en',
            coverUpdatedAt: '2026-10-16T10:00:00Z',
          ),
        );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'ISBN'),
        '0-441-17271-7',
      );
      await tester.tap(find.byTooltip('Look it up'));
      await tester.pumpAndSettle();

      expect(
        backend.adapter.requestsTo('GET', ApiPaths.isbnLookup(dune)),
        hasLength(1),
      );
      expect(find.widgetWithText(TextFormField, 'Dune'), findsOneWidget);
      expect(
        find.widgetWithText(TextFormField, 'Frank Herbert'),
        findsOneWidget,
      );
      expect(find.text('Set on the desert planet Arrakis.'), findsOneWidget);
      expect(find.text('Science fiction'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);

      await save(tester, 'Add a book');

      expect(
        backend.adapter
            .requestsTo('POST', ApiPaths.books(Ids.groupId))
            .single
            .jsonMap,
        {
          'title': 'Dune',
          'author': 'Frank Herbert',
          'description': 'Set on the desert planet Arrakis.',
          'isbn': dune,
          'genre': 'sci_fi',
          'language': 'en',
          'owner_id': null,
          'holder_id': null,
        },
      );
      // The found cover is saved by the server, from the book's ISBN.
      expect(
        backend.adapter.requestsTo('POST', ApiPaths.bookIsbnCover(Ids.bookId)),
        hasLength(1),
      );
    });

    testWidgets('asks before replacing what was typed', (tester) async {
      await open(tester, Routes.newBook(Ids.groupId));
      backend.adapter.onJson(
        'GET',
        ApiPaths.isbnLookup(dune),
        isbnLookupJson(),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'My Dune',
      );
      await tester.enterText(find.widgetWithText(TextFormField, 'ISBN'), dune);
      await tester.tap(find.byTooltip('Look it up'));
      await tester.pumpAndSettle();

      expect(find.text('Use the details found?'), findsOneWidget);
      await tester.tap(find.text('Keep mine'));
      await tester.pumpAndSettle();

      // Mine stays; the empty fields are filled.
      expect(find.widgetWithText(TextFormField, 'My Dune'), findsOneWidget);
      expect(
        find.widgetWithText(TextFormField, 'Frank Herbert'),
        findsOneWidget,
      );
    });

    testWidgets("says when the ISBN isn't valid or isn't found", (
      tester,
    ) async {
      await open(tester, Routes.newBook(Ids.groupId));
      backend.adapter.onProblem(
        'GET',
        ApiPaths.isbnLookup(dune),
        404,
        'not_found',
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'ISBN'),
        '9780441172718',
      );
      await tester.tap(find.byTooltip('Look it up'));
      await tester.pumpAndSettle();
      expect(
        find.text("That isn't a valid ISBN. Check the 10 or 13 digits."),
        findsOneWidget,
      );
      expect(
        backend.adapter.requests.where((r) => r.path.contains('isbn')),
        isEmpty,
      );

      await tester.enterText(find.widgetWithText(TextFormField, 'ISBN'), dune);
      await tester.tap(find.byTooltip('Look it up'));
      await tester.pumpAndSettle();
      expect(
        find.text('No book found for this ISBN. Fill in the details yourself.'),
        findsOneWidget,
      );
    });

    testWidgets("adds Bea's book, which Cris has, with a photo", (
      tester,
    ) async {
      await open(
        tester,
        Routes.newBook(Ids.groupId),
        overrides: [coverPickerProvider.overrideWithValue((_) async => photo)],
      );
      backend.adapter
        ..onJson(
          'POST',
          ApiPaths.books(Ids.groupId),
          bookJson(owner: bea, holder: cris),
          status: 201,
        )
        ..onJson(
          'PUT',
          ApiPaths.bookCover(Ids.bookId),
          bookJson(
            owner: bea,
            holder: cris,
            coverUpdatedAt: '2026-10-16T10:00:00Z',
          ),
        );

      await tapText(tester, 'Take a photo');
      expect(find.text('Remove'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Dune',
      );
      await pick(tester, 'Genre', 'Classics');
      await pick(tester, 'Language', 'Română');
      await pick(tester, 'Owner', 'Bea');
      await pick(tester, 'Who has it now', 'Cris');
      await save(tester, 'Add a book');

      final body = backend.adapter
          .requestsTo('POST', ApiPaths.books(Ids.groupId))
          .single
          .jsonMap;
      expect(body['genre'], 'classics');
      expect(body['language'], 'ro');
      expect(body['owner_id'], Ids.beaId);
      expect(body['holder_id'], Ids.crisId);
      final upload = backend.adapter
          .requestsTo('PUT', ApiPaths.bookCover(Ids.bookId))
          .single;
      expect(upload.body, contains('filename="cover.jpg"'));
    });

    testWidgets('the owner having it means it is with its owner', (
      tester,
    ) async {
      await open(tester, Routes.newBook(Ids.groupId));
      backend.adapter.onJson(
        'POST',
        ApiPaths.books(Ids.groupId),
        bookJson(owner: bea),
        status: 201,
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Dune',
      );
      await pick(tester, 'Who has it now', 'Bea');
      await pick(tester, 'Owner', 'Bea');
      await save(tester, 'Add a book');

      final body = backend.adapter
          .requestsTo('POST', ApiPaths.books(Ids.groupId))
          .single
          .jsonMap;
      expect((body['owner_id'], body['holder_id']), (Ids.beaId, null));
    });
  });

  group('editing a book', () {
    testWidgets('gives it to Bea and lends it on, the owner change last', (
      tester,
    ) async {
      await open(
        tester,
        Routes.editBook(Ids.groupId, Ids.bookId),
        books: [bookJson(isbn: dune, language: 'en')],
      );
      backend.adapter
        ..onJson('PUT', ApiPaths.book(Ids.bookId), bookJson(owner: bea))
        ..onJson('POST', ApiPaths.handover(Ids.bookId), bookJson(holder: cris));

      await pick(tester, 'Who has it now', 'Cris');
      await pick(tester, 'Owner', 'Bea');
      await save(tester, 'Save');

      final puts = backend.adapter.requestsTo('PUT', ApiPaths.book(Ids.bookId));
      expect(
        [for (final put in puts) put.jsonMap['owner_id']],
        [null, Ids.beaId],
      );
      expect(puts.first.jsonMap['isbn'], dune);
      expect(
        backend.adapter
            .requestsTo('POST', ApiPaths.handover(Ids.bookId))
            .single
            .jsonMap,
        {'to_user_id': Ids.crisId},
      );
    });

    testWidgets('removes the cover', (tester) async {
      await open(
        tester,
        Routes.editBook(Ids.groupId, Ids.bookId),
        books: [bookJson(coverUpdatedAt: '2026-10-16T10:00:00Z')],
      );
      backend.adapter
        ..onJson('PUT', ApiPaths.book(Ids.bookId), bookJson())
        ..onJson('DELETE', ApiPaths.bookCover(Ids.bookId), bookJson());

      await tapText(tester, 'Remove');
      expect(find.text('Remove'), findsNothing);
      await save(tester, 'Save');

      expect(
        backend.adapter.requestsTo('DELETE', ApiPaths.bookCover(Ids.bookId)),
        hasLength(1),
      );
    });
  });

  group('the book page', () {
    testWidgets('shows the details and rates the book', (tester) async {
      await open(
        tester,
        Routes.book(Ids.groupId, Ids.bookId),
        books: [
          bookJson(
            isbn: dune,
            genre: 'sci_fi',
            language: 'ro',
            ratingAverage: 4.5,
            ratingCount: 2,
          ),
        ],
      );
      backend.adapter
        ..onJson(
          'PUT',
          ApiPaths.bookRating(Ids.bookId),
          bookJson(ratingAverage: 4.3, ratingCount: 3, myRating: 4),
        )
        ..onJson(
          'DELETE',
          ApiPaths.bookRating(Ids.bookId),
          bookJson(ratingAverage: 4.5, ratingCount: 2),
        );

      expect(find.text('Science fiction'), findsOneWidget);
      expect(find.text('Română'), findsOneWidget);
      expect(find.text('ISBN $dune'), findsOneWidget);
      expect(find.text('4.5 · 2 ratings'), findsOneWidget);
      expect(find.text('Read it? Tap the stars.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('star-4')));
      await tester.pumpAndSettle();
      expect(
        backend.adapter
            .requestsTo('PUT', ApiPaths.bookRating(Ids.bookId))
            .single
            .jsonMap,
        {'stars': 4},
      );
      expect(find.text('4.3 · 3 ratings'), findsOneWidget);

      // Tapping my rating again takes it back.
      await tester.tap(find.byKey(const ValueKey('star-4')));
      await tester.pumpAndSettle();
      expect(
        backend.adapter.requestsTo('DELETE', ApiPaths.bookRating(Ids.bookId)),
        hasLength(1),
      );
      expect(find.text('4.5 · 2 ratings'), findsOneWidget);
    });

    testWidgets('loads the cover with the signed-in client', (tester) async {
      await open(
        tester,
        Routes.book(Ids.groupId, Ids.bookId),
        books: [bookJson(coverUpdatedAt: '2026-10-16T10:00:00Z')],
      );

      expect(
        backend.adapter.requestsTo('GET', ApiPaths.bookCover(Ids.bookId)),
        hasLength(1),
      );
      // The fake server has no image: the placeholder stays.
      expect(find.byIcon(Icons.menu_book), findsWidgets);
    });
  });

  group('the shelf', () {
    final shelf = [
      bookJson(genre: 'sci_fi', language: 'en'),
      bookJson(
        id: Ids.otherBookId,
        title: 'Maitreyi',
        author: 'Mircea Eliade',
        genre: 'classics',
        language: 'ro',
        ratingAverage: 4.5,
        ratingCount: 2,
      ),
    ];

    List<String> titles(WidgetTester tester) => [
      for (final text in tester.widgetList<Text>(
        find.descendant(of: find.byType(ListTile), matching: find.byType(Text)),
      ))
        if (text.data == 'Dune' || text.data == 'Maitreyi') text.data!,
    ];

    testWidgets('sorts by rating, and filters by genre and language', (
      tester,
    ) async {
      await open(tester, Routes.groupBooks(Ids.groupId), books: shelf);

      expect(titles(tester), ['Dune', 'Maitreyi']);
      expect(find.text('4.5 · 2 ratings'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('sort-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Best rated').last);
      await tester.pumpAndSettle();
      expect(titles(tester), ['Maitreyi', 'Dune']);

      await tester.tap(find.byKey(const ValueKey('genre-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Science fiction').last);
      await tester.pumpAndSettle();
      expect(titles(tester), ['Dune']);

      await tester.tap(find.byKey(const ValueKey('genre-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All genres').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('language-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Română').last);
      await tester.pumpAndSettle();
      expect(titles(tester), ['Maitreyi']);
    });

    testWidgets('searches ISBNs too', (tester) async {
      await open(
        tester,
        Routes.groupBooks(Ids.groupId),
        books: [
          bookJson(isbn: dune),
          ...shelf.skip(1),
        ],
      );

      await tester.enterText(find.byType(TextField), '978-0441');
      await tester.pumpAndSettle();

      expect(titles(tester), ['Dune']);
    });
  });
}
