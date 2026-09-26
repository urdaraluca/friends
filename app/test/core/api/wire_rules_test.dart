// Wire-rule spike (contract section 12, ADR 0003): what the generated client
// actually puts on the wire, checked against a fake adapter.
//
// `spike/generated/` is real swagger_parser output (same settings as
// app/swagger_parser.yaml) for a small FastAPI schema with the shapes later
// milestones need, since the M4 API has no list or enum query parameters.
// See spike/README.md.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/api_instant.dart';
import 'package:friends/core/api/api_providers.dart';
import 'package:friends/core/api/date_only.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/api/generated/models/me_update.dart';
import 'package:friends/core/network/dio_provider.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_http_adapter.dart';
import '../../helpers/test_backend.dart';
import 'spike/generated/clients/spike_client.dart';
import 'spike/generated/models/activity_sort.dart';
import 'spike/generated/models/activity_status.dart';
import 'spike/generated/models/event_kind.dart';
import 'spike/generated/models/spike_item.dart';
import 'spike/generated/models/spike_write.dart';

/// The server's `ApiDate` pattern (contract section 1.3).
final _apiDate = RegExp(
  r'^(\d{4}-\d{2}-\d{2})(?:[T ]00:00(?::00(?:\.0{1,6})?)?Z?)?$',
);

/// An ISO 8601 instant in UTC with a `Z` suffix.
final _utcInstant = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$');

const _itemPath = '/api/v1/spike/items/0190c3a5-0000-7000-8000-000000000009';

void main() {
  late TestBackend backend;
  late FakeHttpClientAdapter adapter;
  late ProviderContainer container;
  late SpikeClient spike;

  Map<String, Object?> itemJson() => {
    'id': '0190c3a5-0000-7000-8000-000000000009',
    'title': 'Movie night',
    'status': 'planning',
    'due_date': '2026-10-01',
    'starts_at': '2026-10-01T16:00:00.123456Z',
    'notes': null,
  };

  setUp(() {
    backend = TestBackend(storedRefreshToken: 'refresh-0');
    backend.holder.set('access-0', expiresIn: const Duration(minutes: 15));
    adapter = backend.adapter
      ..onJson('GET', '/api/v1/spike/items', <Object?>[])
      ..onJson('PUT', _itemPath, itemJson());
    container = backend.container();
    // The app's main Dio: same options and interceptors as production.
    spike = SpikeClient(container.read(dioProvider));
  });

  test('1. list query parameters repeat the key (ListFormat.multi)', () async {
    await spike.listSpikeItems(
      from: DateOnly.of(2026, 10, 1),
      status: [ActivityStatus.idea, ActivityStatus.planning],
    );

    expect(adapter.last.query, contains('status=idea&status=planning'));
    expect(adapter.last.queryParametersAll['status'], ['idea', 'planning']);
    expect(adapter.last.query, isNot(contains('status%5B%5D')));
  });

  group('2. enum query values use their wire names', () {
    test('in lists (Dio calls toString())', () async {
      await spike.listSpikeItems(
        from: DateOnly.of(2026, 10, 1),
        kinds: [EventKind.oneTime, EventKind.birthday],
      );

      expect(adapter.last.query, contains('kinds=one_time&kinds=birthday'));
      expect(adapter.last.query, isNot(contains('oneTime')));
    });

    test('single values (retrofit calls toJson())', () async {
      await spike.listSpikeItems(
        from: DateOnly.of(2026, 10, 1),
        sort: ActivitySort.dueDate,
      );

      expect(adapter.last.queryParametersAll['sort'], ['due_date']);
      expect(adapter.last.query, isNot(contains('dueDate')));
    });

    test('schema defaults are sent explicitly', () async {
      await spike.listSpikeItems(from: DateOnly.of(2026, 10, 1));

      expect(adapter.last.queryParametersAll['sort'], ['created_at']);
      expect(adapter.last.queryParametersAll['include_subcategories'], [
        'true',
      ]);
    });

    test(r'a single $unknown value throws before anything is sent', () async {
      await expectLater(
        spike.listSpikeItems(
          from: DateOnly.of(2026, 10, 1),
          sort: ActivitySort.$unknown,
        ),
        throwsStateError,
      );
      expect(adapter.requests, isEmpty);
    });
  });

  test('query booleans are true/false (contract section 1.4)', () async {
    await spike.listSpikeItems(
      from: DateOnly.of(2026, 10, 1),
      includeSubcategories: false,
    );

    expect(adapter.last.queryParametersAll['include_subcategories'], ['false']);
  });

  group('3. dates', () {
    test(
      'a DateOnly query value is a UTC midnight the server accepts',
      () async {
        await spike.listSpikeItems(
          from: DateOnly.of(2026, 10, 1),
          dueBefore: DateOnly.parse('2026-12-31'),
        );

        final query = adapter.last.queryParametersAll;
        expect(query['from'], ['2026-10-01T00:00:00.000Z']);
        expect(query['due_before'], ['2026-12-31T00:00:00.000Z']);
        expect(
          _apiDate.firstMatch(query['from']!.single)?.group(1),
          '2026-10-01',
        );
      },
    );

    test('a DateOnly body value is a UTC midnight', () async {
      await spike.updateSpikeItem(
        itemId: '0190c3a5-0000-7000-8000-000000000009',
        body: SpikeWrite(title: 'Hike', dueDate: DateOnly.of(2026, 3, 5)),
      );

      final dueDate = adapter.last.jsonMap['due_date']! as String;
      expect(dueDate, '2026-03-05T00:00:00.000Z');
      expect(_apiDate.firstMatch(dueDate)?.group(1), '2026-03-05');
    });

    test('every date of a year goes out as a midnight of that date', () {
      // A local DateTime(y, m, d) is 01:00 on the days DST starts at
      // midnight (e.g. 2026-09-06 in America/Santiago), whatever the zone of
      // the machine running this test; DateOnly must not depend on it.
      for (
        var day = DateOnly.of(2026, 1, 1);
        day.year == 2026;
        day = DateOnly.of(day.year, day.month, day.day + 1)
      ) {
        final wire = day.toIso8601String();
        expect(wire, endsWith('T00:00:00.000Z'), reason: wire);
        expect(_apiDate.firstMatch(wire)?.group(1), DateOnly.format(day));
      }
    });

    test('dates from the server parse to a local DateTime; DateOnly.from '
        'makes them sendable again', () async {
      final item = await spike.updateSpikeItem(
        itemId: '0190c3a5-0000-7000-8000-000000000009',
        body: const SpikeWrite(title: 'x'),
      );

      expect(item.dueDate!.isUtc, isFalse);
      expect(DateOnly.format(item.dueDate!), '2026-10-01');
      expect(DateOnly.from(item.dueDate!), DateOnly.of(2026, 10, 1));

      // In Santiago, "2026-09-06" parses to 01:00 local (no local midnight
      // that day). Sent back as is, the server would reject it.
      final inGap = DateTime(2026, 9, 6, 1);
      expect(inGap.toIso8601String(), isNot(matches(_apiDate)));
      expect(
        DateOnly.from(inGap).toIso8601String(),
        '2026-09-06T00:00:00.000Z',
      );
      expect(DateOnly.fromNullable(null), isNull);
    });

    test('YYYY-MM-DD formatting and parsing', () {
      expect(DateOnly.format(DateOnly.of(2026, 2, 3)), '2026-02-03');
      expect(DateOnly.parse('2024-02-29'), DateTime.utc(2024, 2, 29));
      expect(DateOnly.tryParse('2026-02-30'), isNull);
      expect(DateOnly.tryParse('2026-10-01T00:00:00Z'), isNull);
      expect(() => DateOnly.parse('1/10/2026'), throwsFormatException);
      expect(
        DateOnly.from(DateTime(2026, 10, 1, 23, 59)),
        DateTime.utc(2026, 10),
      );
      expect(DateOnly.today().isUtc, isTrue);
    });

    test('dates compare by calendar date only', () {
      final utc = DateOnly.of(2026, 10, 1);
      final local = DateTime(2026, 10, 1, 12);

      expect(DateOnly.isSameDay(utc, local), isTrue);
      expect(DateOnly.compare(utc, local), 0);
      expect(DateOnly.compare(utc, DateTime(2026, 10, 2)), lessThan(0));
      expect(DateOnly.compare(DateOnly.of(2027, 1, 1), local), greaterThan(0));
    });
  });

  group('4. instants', () {
    test('ApiInstant sends UTC with Z, in queries and bodies', () async {
      final local = DateTime(2026, 10, 1, 18, 30);

      await spike.listSpikeItems(
        from: DateOnly.of(2026, 10, 1),
        changedAfter: ApiInstant.of(local),
      );
      final query = adapter.last.queryParametersAll['changed_after']!.single;
      expect(query, matches(_utcInstant));
      expect(DateTime.parse(query), local.toUtc());

      await spike.updateSpikeItem(
        itemId: '0190c3a5-0000-7000-8000-000000000009',
        body: SpikeWrite(title: 'x', startsAt: ApiInstant.of(local)),
      );
      final body = adapter.last.jsonMap['starts_at']! as String;
      expect(body, matches(_utcInstant));
      expect(DateTime.parse(body).isAtSameMomentAs(local), isTrue);
    });

    test('a local DateTime would go out without an offset (422)', () {
      final local = DateTime(2026, 10, 1, 18, 30);

      expect(local.toIso8601String(), isNot(matches(_utcInstant)));
      expect(ApiInstant.of(local).toIso8601String(), matches(_utcInstant));
      expect(ApiInstant.ofNullable(null), isNull);
    });

    test('instants from the server keep microseconds and UTC', () async {
      final item = await spike.updateSpikeItem(
        itemId: '0190c3a5-0000-7000-8000-000000000009',
        body: const SpikeWrite(title: 'x'),
      );

      expect(item.startsAt, DateTime.utc(2026, 10, 1, 16, 0, 0, 123, 456));
      expect(item.startsAt!.isUtc, isTrue);
    });
  });

  group('5. PUT bodies include explicit nulls', () {
    test('in the spike model', () async {
      await spike.updateSpikeItem(
        itemId: '0190c3a5-0000-7000-8000-000000000009',
        body: const SpikeWrite(title: 'x'),
      );

      expect(adapter.last.jsonMap, {
        'title': 'x',
        'due_date': null,
        'starts_at': null,
        'notes': null,
        'status': 'idea',
      });
    });

    test('in the real MeUpdate', () async {
      adapter.onJson('PUT', ApiPaths.me, meJson());

      await container
          .read(usersClientProvider)
          .updateMe(
            body: const MeUpdate(displayName: 'Ana', timezone: 'UTC'),
          );

      expect(adapter.last.jsonMap, {
        'display_name': 'Ana',
        'timezone': 'UTC',
        'birthday': null,
        'locale': null,
        'avatar_url': null,
      });
    });

    test('nested models are serialized', () async {
      adapter.onJson('PUT', ApiPaths.me, meJson());

      await container
          .read(usersClientProvider)
          .updateMe(
            body: MeUpdate.fromJson({
              'display_name': 'Ana',
              'timezone': 'UTC',
              'birthday': {'month': 2, 'day': 29, 'year': null},
            }),
          );

      expect(adapter.last.jsonMap['birthday'], {
        'month': 2,
        'day': 29,
        'year': null,
      });
    });
  });

  test('6. problem+json is decoded into a ProblemException', () async {
    adapter.onProblem(
      'PUT',
      _itemPath,
      422,
      ErrorCodes.validationError,
      errors: [
        {
          'field': 'due_date',
          'message': 'Input should be a valid date',
          'type': 'date_from_datetime_inexact',
        },
      ],
    );

    try {
      await apiCall(
        () => spike.updateSpikeItem(
          itemId: '0190c3a5-0000-7000-8000-000000000009',
          body: const SpikeWrite(title: 'x'),
        ),
      );
      fail('Expected a ProblemException');
    } on ProblemException catch (e) {
      expect(e.status, 422);
      expect(e.code, ErrorCodes.validationError);
      expect(e.errors.single.field, 'due_date');
      expect(e.errors.single.type, 'date_from_datetime_inexact');
    }
  });

  test('unknown enum values from the server do not crash', () {
    final item = SpikeItem.fromJson({...itemJson(), 'status': 'archived'});

    expect(item.status, ActivityStatus.$unknown);
  });
}
