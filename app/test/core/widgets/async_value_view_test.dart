import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<void> pumpView(
    WidgetTester tester,
    AsyncValue<String> value, {
    VoidCallback? onRetry,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AsyncValueView(value: value, onRetry: onRetry, data: Text.new),
        ),
      ),
    );
  }

  group('AsyncValueView', () {
    testWidgets('shows a spinner while loading', (tester) async {
      await pumpView(tester, const AsyncLoading());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows the data', (tester) async {
      await pumpView(tester, const AsyncData('hello'));

      expect(find.text('hello'), findsOneWidget);
    });

    testWidgets('shows network errors with Retry', (tester) async {
      var retries = 0;
      await pumpView(
        tester,
        const AsyncError(NetworkException(), StackTrace.empty),
        onRetry: () => retries++,
      );

      expect(find.text("Can't reach the server"), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retries, 1);
    });

    testWidgets('shows a friendly message for problems', (tester) async {
      await pumpView(
        tester,
        const AsyncError(
          ProblemException(status: 403, code: ErrorCodes.forbidden),
          StackTrace.empty,
        ),
      );

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(
        find.text("You don't have permission to do that."),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsNothing);
    });

    group('with a real provider', () {
      /// Each fetch waits for the next completer in [replies].
      late List<Completer<String>> replies;
      late FutureProvider<String> provider;

      setUp(() {
        replies = [];
        provider = FutureProvider<String>((ref) {
          final reply = Completer<String>();
          replies.add(reply);
          return reply.future;
        });
      });

      Future<void> pumpProvider(WidgetTester tester) => tester.pumpWidget(
        ProviderScope(
          retry: (retryCount, error) => null,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => AsyncValueView(
                  value: ref.watch(provider),
                  onRetry: () => ref.invalidate(provider),
                  data: Text.new,
                ),
              ),
            ),
          ),
        ),
      );

      testWidgets('Retry shows the spinner until the retry finishes', (
        tester,
      ) async {
        await pumpProvider(tester);
        replies.last.completeError(const NetworkException());
        await tester.pump();
        expect(find.text("Can't reach the server"), findsOneWidget);

        await tester.tap(find.text('Retry'));
        await tester.pump();

        expect(replies, hasLength(2));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Retry'), findsNothing);

        replies.last.complete('back online');
        await tester.pump();
        expect(find.text('back online'), findsOneWidget);
      });

      testWidgets('a refresh keeps the previous data on screen', (
        tester,
      ) async {
        await pumpProvider(tester);
        replies.last.complete('first');
        await tester.pump();

        ProviderScope.containerOf(tester.element(find.text('first')))
            .invalidate(provider);
        await tester.pump();

        expect(replies, hasLength(2));
        expect(find.text('first'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);

        replies.last.complete('second');
        await tester.pumpAndSettle();
        expect(find.text('second'), findsOneWidget);
      });
    });
  });
}
