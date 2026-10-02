import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/features/books/presentation/book_detail_screen.dart';
import 'package:friends/features/books/presentation/books_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_auth_controller.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/test_backend.dart';

void main() {
  late TestBackend backend;

  final bea = userPublicJson(id: Ids.beaId, displayName: 'Bea');
  final cris = userPublicJson(id: Ids.crisId, displayName: 'Cris');

  setUp(() => backend = TestBackend());

  /// Signed in as Ana, in a book club whose shelf holds [books].
  Future<ProviderContainer> open(
    WidgetTester tester,
    String location, {
    List<Map<String, Object?>>? books,
  }) async {
    tester.view
      ..physicalSize = const Size(800, 1600)
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
      ],
      location: location,
    );
  }

  Finder navLabel(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  group('the Books tab', () {
    testWidgets('comes second in a book club and lists the shelf', (
      tester,
    ) async {
      final container = await open(
        tester,
        Routes.groupBacklog(Ids.groupId),
        books: [
          bookJson(),
          bookJson(
            id: Ids.otherBookId,
            title: 'Middlemarch',
            author: 'George Eliot',
            owner: bea,
            holder: userPublicJson(),
            heldSince: '2026-09-28T10:00:00Z',
            queue: [queueEntryJson(Ids.crisId, 'Cris')],
            canEdit: false,
          ),
        ],
      );

      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(
        [for (final d in bar.destinations) (d as NavigationDestination).label],
        ['Backlog', 'Books', 'Calendar', 'Wheel', 'Group'],
      );
      await tester.tap(navLabel('Books'));
      await tester.pumpAndSettle();

      expect(currentLocation(container), '/groups/${Ids.groupId}/books');
      expect(find.byType(BooksScreen), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      expect(find.text('Dune'), findsOneWidget);
      expect(find.text('Frank Herbert\nAvailable, with Ana'), findsOneWidget);
      expect(find.text('George Eliot\nYou have it'), findsOneWidget);
      expect(find.text('1 waiting'), findsOneWidget);
    });

    testWidgets('filters and searches on the device', (tester) async {
      await open(
        tester,
        Routes.groupBooks(Ids.groupId),
        books: [
          bookJson(),
          bookJson(
            id: Ids.otherBookId,
            title: 'Middlemarch',
            author: 'George Eliot',
            owner: bea,
            holder: cris,
            inMyQueue: true,
            queue: [queueEntryJson(Ids.anaId, 'Ana')],
          ),
        ],
      );

      await tester.tap(find.widgetWithText(ChoiceChip, 'Available'));
      await tester.pumpAndSettle();
      expect(find.text('Dune'), findsOneWidget);
      expect(find.text('Middlemarch'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, "I'm waiting"));
      await tester.pumpAndSettle();
      expect(find.text('Dune'), findsNothing);
      expect(find.text('Middlemarch'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.enterText(find.byType(TextField), 'eliot');
      await tester.pumpAndSettle();
      expect(find.text('Dune'), findsNothing);
      expect(find.text('Middlemarch'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'tolstoy');
      await tester.pumpAndSettle();
      expect(find.text('No books match.'), findsOneWidget);
    });

    testWidgets('an empty shelf invites adding a book', (tester) async {
      await open(tester, Routes.groupBooks(Ids.groupId));

      expect(find.text('No books yet'), findsOneWidget);
      expect(find.text('Add a book'), findsOneWidget);
    });

    testWidgets('a general group has no Books tab', (tester) async {
      backend.stubGroup();
      await tester.pumpFriendsApp(
        overrides: [
          ...backend.overrides,
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedIn()),
          ),
        ],
        location: Routes.groupBacklog(Ids.groupId),
      );

      expect(navLabel('Books'), findsNothing);
      expect(navLabel('Backlog'), findsOneWidget);
    });
  });

  group('a book', () {
    testWidgets('lends it to the first in line', (tester) async {
      await open(
        tester,
        Routes.book(Ids.groupId, Ids.bookId),
        books: [
          bookJson(
            description: 'Spice.',
            queue: [
              queueEntryJson(Ids.beaId, 'Bea'),
              queueEntryJson(Ids.crisId, 'Cris'),
            ],
          ),
        ],
      );
      backend.adapter.onJson(
        'POST',
        ApiPaths.handover(Ids.bookId),
        bookJson(
          holder: bea,
          heldSince: '2026-10-02T10:00:00Z',
          queue: [queueEntryJson(Ids.crisId, 'Cris')],
        ),
      );

      expect(find.byType(BookDetailScreen), findsOneWidget);
      expect(find.text('Spice.'), findsOneWidget);
      expect(find.text('1. Bea'), findsOneWidget);
      expect(find.text('2. Cris'), findsOneWidget);
      // My own book: no waiting list for me.
      expect(find.text('Join the waiting list'), findsNothing);

      await tester.tap(find.text('Lend to Bea'));
      await tester.pumpAndSettle();

      expect(
        backend.adapter
            .requestsTo('POST', ApiPaths.handover(Ids.bookId))
            .single
            .jsonMap,
        {'to_user_id': Ids.beaId},
      );
      expect(find.text('Bea has it now'), findsOneWidget);
      expect(find.textContaining('Bea has it since'), findsOneWidget);
      expect(find.text('Lend to Cris'), findsOneWidget);
      expect(find.text('Back with Ana'), findsOneWidget);
    });

    testWidgets('marks it back with its owner', (tester) async {
      await open(
        tester,
        Routes.book(Ids.groupId, Ids.bookId),
        books: [bookJson(holder: bea, heldSince: '2026-10-01T10:00:00Z')],
      );
      backend.adapter.onJson('POST', ApiPaths.handover(Ids.bookId), bookJson());

      await tester.tap(find.text('Back with Ana'));
      await tester.pumpAndSettle();

      expect(
        backend.adapter
            .requestsTo('POST', ApiPaths.handover(Ids.bookId))
            .single
            .jsonMap,
        {'to_user_id': null},
      );
      expect(find.text('Available, with Ana'), findsOneWidget);
    });

    testWidgets('lends it to someone outside the queue', (tester) async {
      await open(
        tester,
        Routes.book(Ids.groupId, Ids.bookId),
        books: [bookJson()],
      );
      backend.adapter.onJson(
        'POST',
        ApiPaths.handover(Ids.bookId),
        bookJson(holder: cris, heldSince: '2026-10-02T10:00:00Z'),
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Who has it now?'));
      await tester.pumpAndSettle();
      // Everyone but its owner.
      expect(
        find.descendant(
          of: find.byType(SimpleDialog),
          matching: find.text('Ana'),
        ),
        findsNothing,
      );
      await tester.tap(find.text('Cris'));
      await tester.pumpAndSettle();

      expect(
        backend.adapter
            .requestsTo('POST', ApiPaths.handover(Ids.bookId))
            .single
            .jsonMap,
        {'to_user_id': Ids.crisId},
      );
      expect(find.text('Cris has it now'), findsOneWidget);
    });

    testWidgets("joins and leaves the waiting list for someone else's", (
      tester,
    ) async {
      final theirs = bookJson(
        owner: bea,
        holder: cris,
        canEdit: false,
        canHandOver: false,
      );
      await open(tester, Routes.book(Ids.groupId, Ids.bookId), books: [theirs]);
      backend.adapter
        ..onJson(
          'PUT',
          ApiPaths.bookQueue(Ids.bookId),
          bookJson(
            owner: bea,
            holder: cris,
            canEdit: false,
            canHandOver: false,
            inMyQueue: true,
            queue: [queueEntryJson(Ids.anaId, 'Ana')],
          ),
        )
        ..onJson('DELETE', ApiPaths.bookQueue(Ids.bookId), theirs);

      expect(find.text('Nobody is waiting.'), findsOneWidget);
      expect(find.textContaining('Lend to'), findsNothing);
      expect(find.byTooltip('More'), findsNothing); // can't edit

      await tester.tap(find.text('Join the waiting list'));
      await tester.pumpAndSettle();
      expect(find.text('Your place in line: 1'), findsOneWidget);

      await tester.tap(find.text('Leave the waiting list'));
      await tester.pumpAndSettle();
      expect(find.text('Nobody is waiting.'), findsOneWidget);
      expect(
        backend.adapter.requestsTo('DELETE', ApiPaths.bookQueue(Ids.bookId)),
        hasLength(1),
      );
    });

    testWidgets('a missing book says so', (tester) async {
      await open(tester, Routes.book(Ids.groupId, Ids.bookId));

      expect(
        find.text("This book isn't in the archive anymore."),
        findsOneWidget,
      );
    });
  });

  group('the book form', () {
    testWidgets('adds a book and opens it', (tester) async {
      final container = await open(tester, Routes.groupBooks(Ids.groupId));
      backend.adapter.onJson(
        'POST',
        ApiPaths.books(Ids.groupId),
        bookJson(title: 'Solenoid', author: 'Mircea Cărtărescu'),
        status: 201,
      );

      await tester.tap(find.text('Add a book'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add a book'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a title.'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        ' Solenoid ',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Author'),
        'Mircea Cărtărescu',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add a book'));
      await tester.pumpAndSettle();

      expect(
        backend.adapter
            .requestsTo('POST', ApiPaths.books(Ids.groupId))
            .single
            .jsonMap,
        {
          'title': 'Solenoid',
          'author': 'Mircea Cărtărescu',
          'description': null,
        },
      );
      expect(
        currentLocation(container),
        '/groups/${Ids.groupId}/books/${Ids.bookId}',
      );
      expect(find.byType(BookDetailScreen), findsOneWidget);
    });
  });
}
