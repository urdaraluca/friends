import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/features/calendar/domain/rrule_spec.dart';
import 'package:friends/features/feed/domain/feed_text.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/api_fixtures.dart';
import '../helpers/fake_auth_controller.dart';
import '../helpers/pump_app.dart';
import '../helpers/test_backend.dart';

Map<String, Object?> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, Object?>;

/// The `{name}` placeholders of an ICU message (not the plural keywords).
Set<String> _placeholders(String message) => {
  for (final match in RegExp(r'(?<![\w=])\{(\w+)(?=[,}])').allMatches(message))
    match.group(1)!,
};

void main() {
  setUpAll(() => initializeDateFormatting('ro'));
  tearDown(() => Intl.defaultLocale = null);

  group('the Romanian strings', () {
    final en = _arb('en');
    final ro = _arb('ro');
    final keys = {
      for (final key in en.keys)
        if (!key.startsWith('@')) key,
    };

    test('cover every English key, and only those', () {
      final roKeys = {
        for (final key in ro.keys)
          if (!key.startsWith('@')) key,
      };
      expect(roKeys.difference(keys), isEmpty);
      expect(keys.difference(roKeys), isEmpty);
    });

    test('use the same placeholders', () {
      for (final key in keys) {
        expect(
          _placeholders(ro[key]! as String),
          _placeholders(en[key]! as String),
          reason: key,
        );
      }
    });

    test('have the three Romanian plural forms', () {
      final l10n = lookupAppLocalizations(const Locale('ro'));
      expect(l10n.memberCount(1), '1 membru');
      expect(l10n.memberCount(3), '3 membri');
      expect(l10n.memberCount(19), '19 membri');
      expect(l10n.memberCount(20), '20 de membri');
      expect(l10n.memberCount(101), '101 membri');
    });
  });

  group('in Romanian', () {
    test('feed sentences put the names where Romanian wants them', () {
      final item = FeedItem.fromJson(
        feedItemJson(action: 'poll.option_added', subjectTitle: 'Ce film?'),
      );
      final spans =
          Intl.withLocale('ro', () => feedSentence(item)) as List<FeedSpan>;
      expect(
        spans.map((s) => s.text).join(),
        'Ana a adăugat o opțiune la „Ce film?”',
      );
      expect(spans.where((s) => s.bold).map((s) => s.text), [
        'Ana',
        'o opțiune',
        '„Ce film?”',
      ]);
    });

    test('repeat rules describe themselves', () {
      String describe(RecurrenceSpec spec) =>
          Intl.withLocale('ro', spec.describe) as String;
      expect(
        describe(
          const RecurrenceSpec(
            frequency: RepeatFrequency.weekly,
            weekdays: {1, 4},
          ),
        ),
        'În fiecare săptămână, luni și joi',
      );
      expect(
        describe(
          const RecurrenceSpec(
            frequency: RepeatFrequency.monthly,
            interval: 2,
            monthlyDay: MonthlyByWeekday(-1, 5),
            end: RepeatCount(20),
          ),
        ),
        'La fiecare 2 luni, în ultima vineri, de 20 de ori',
      );
    });

    testWidgets("the app follows the profile's language", (tester) async {
      final backend = TestBackend()
        ..stubGroups([groupSummaryJson(memberCount: 5, myRole: 'owner')]);
      await tester.pumpFriendsApp(
        overrides: [
          ...backend.overrides,
          authControllerProvider.overrideWith(
            () => FakeAuthController(
              Authenticated(Me.fromJson(meJson(locale: 'ro'))),
            ),
          ),
        ],
        location: Routes.groups,
      );

      expect(find.text('Grupurile tale'), findsOneWidget);
      expect(find.text('5 membri'), findsOneWidget);
      expect(find.text('Proprietar'), findsOneWidget);
      expect(find.text('Grup nou'), findsOneWidget);
    });
  });
}
