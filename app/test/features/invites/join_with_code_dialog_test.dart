import 'package:flutter_test/flutter_test.dart';
import 'package:friends/features/invites/presentation/join_with_code_dialog.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/pump_app.dart';

void main() {
  /// Opens the dialog, types [input] and taps Continue. Returns the code
  /// the dialog closed with, or `'<open>'` while it stays open.
  Future<String?> submit(WidgetTester tester, String input) async {
    String? result = '<open>';
    await tester.pumpApp(
      Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await showDialog<String>(
              context: context,
              builder: (context) => const JoinWithCodeDialog(),
            );
          },
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), input);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    return result;
  }

  group('JoinWithCodeDialog', () {
    // The same cases as backend/tests/api/test_invites.py (contract 4.7).
    const valid = {
      'abcd-efgh-jk': 'ABCDEFGHJK',
      ' abcd efgh ik ': 'ABCDEFGH1K',
      '0O1IL23456': '0011123456',
    };
    for (final MapEntry(key: input, value: code) in valid.entries) {
      testWidgets('normalizes "$input" to $code like the server', (
        tester,
      ) async {
        expect(await submit(tester, input), code);
      });
    }

    for (final input in ['ABCDEFGHJ', 'ABCDEFGHJU']) {
      testWidgets('rejects "$input"', (tester) async {
        expect(await submit(tester, input), '<open>');
        expect(
          find.text("That doesn't look like an invite code."),
          findsOneWidget,
        );
      });
    }

    testWidgets('accepts a pasted invite link', (tester) async {
      expect(
        await submit(tester, 'https://friends.example.com/join/abcde-fghjk'),
        'ABCDEFGHJK',
      );
    });

    testWidgets('asks for a code when empty', (tester) async {
      expect(await submit(tester, '  '), '<open>');
      expect(find.text('Enter an invite code.'), findsOneWidget);
    });
  });
}
