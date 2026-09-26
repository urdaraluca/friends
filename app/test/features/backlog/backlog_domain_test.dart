import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/features/backlog/domain/activity_filter.dart';
import 'package:friends/features/backlog/domain/activity_rules.dart';
import 'package:friends/features/backlog/domain/category_index.dart';
import 'package:friends/features/backlog/domain/field_values.dart';

import '../../helpers/api_fixtures.dart';

FieldDef def(FieldType type, {List<String>? options, num? min, num? max}) =>
    FieldDef(
      key: 'k',
      label: 'K',
      type: type,
      options: options,
      min: min,
      max: max,
    );

void main() {
  group('ActivityFilter', () {
    test('sends the active statuses by default, the archive on request', () {
      const filter = ActivityFilter();

      expect(filter.queryStatuses, [
        ActivityStatus.idea,
        ActivityStatus.planning,
        ActivityStatus.scheduled,
      ]);
      expect(filter.isFiltered, isFalse);
      expect(
        filter.copyWith(showArchived: true).queryStatuses,
        ActivityStatus.$valuesDefined,
      );
    });

    test('compares by value, so pagers are reused for equal filters', () {
      final a = const ActivityFilter().copyWith(
        statuses: {ActivityStatus.planning, ActivityStatus.idea},
        query: 'dune',
      );
      final b = const ActivityFilter().copyWith(
        statuses: {ActivityStatus.idea, ActivityStatus.planning},
        query: 'dune',
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(a.copyWith(onlyMine: true)));
    });

    test('nullable fields can be cleared', () {
      final filter = const ActivityFilter().copyWith(
        categoryId: () => 'c',
        costMax: () => 40,
      );

      expect(filter.isFiltered, isTrue);
      final cleared = filter.copyWith(
        categoryId: () => null,
        costMax: () => null,
      );
      expect(cleared, const ActivityFilter());
    });

    test('a blank query sends no q', () {
      expect(const ActivityFilter(query: '   ').queryText, isNull);
      expect(const ActivityFilter(query: ' dune ').queryText, 'dune');
    });
  });

  group('FieldValues', () {
    test('parse turns input text into JSON values; empty clears', () {
      expect(FieldValues.parse(def(FieldType.text), '  hi '), 'hi');
      expect(FieldValues.parse(def(FieldType.text), '   '), isNull);
      expect(FieldValues.parse(def(FieldType.number), '7,5'), 7.5);
      expect(FieldValues.parse(def(FieldType.number), '120'), 120);
      expect(FieldValues.parse(def(FieldType.rating), '8.1'), 8.1);
      expect(FieldValues.parse(def(FieldType.year), '1999'), 1999);
    });

    test('validate mirrors the server rules (contract 6.3)', () {
      final rating = def(FieldType.rating);
      expect(FieldValues.validate(rating, '8.1'), isNull);
      expect(FieldValues.validate(rating, '7.25'), 'At most one decimal');
      expect(FieldValues.validate(rating, '11'), 'Between 0 and 10');
      expect(FieldValues.validate(rating, ''), isNull);

      final runtime = def(FieldType.number, min: 1, max: 600);
      expect(FieldValues.validate(runtime, '0'), 'Between 1 and 600');
      expect(FieldValues.validate(runtime, 'abc'), 'Enter a number');

      final year = def(FieldType.year);
      expect(FieldValues.validate(year, '1799'), 'Between 1800 and 2200');
      expect(FieldValues.validate(year, '2026'), isNull);

      final url = def(FieldType.url);
      expect(FieldValues.validate(url, 'imdb.com/title'), isNotNull);
      expect(FieldValues.validate(url, 'https://imdb.com/title'), isNull);

      final genre = def(FieldType.select, options: ['Comedy']);
      expect(FieldValues.validate(genre, 'Comedy'), isNull);
      expect(FieldValues.validate(genre, 'comedy'), 'Pick one of the options');

      expect(
        FieldValues.validate(def(FieldType.text), 'x' * 201),
        'At most 200 characters',
      );
    });

    test('display and toText format stored values', () {
      expect(FieldValues.display(FieldType.rating, 8.1), '⭐ 8.1');
      expect(FieldValues.display(FieldType.rating, 8), '⭐ 8');
      expect(FieldValues.toText(7.0), '7');
      expect(FieldValues.toText(null), '');
      expect(FieldValues.display(FieldType.select, 'Drama'), 'Drama');
    });

    test('keyFromLabel makes a valid key', () {
      expect(FieldValues.keyFromLabel('IMDb rating'), 'imdb_rating');
      expect(FieldValues.keyFromLabel('Runtime (min)'), 'runtime_min');
      expect(FieldValues.keyFromLabel('Țară de origine'), 'tara_de_origine');
      expect(FieldValues.keyFromLabel('3D?'), 'f_3d');
      expect(FieldValues.keyFromLabel('!!!'), '');
      final long = FieldValues.keyFromLabel('a very long label ' * 4);
      expect(long.length, lessThanOrEqualTo(30));
      expect(FieldValues.isValidKey(long), isTrue);
    });
  });

  group('OwnerRules (contract 7.2)', () {
    OwnerRules rules(Role role, String? owner) =>
        OwnerRules(myRole: role, myUserId: 'me', ownerId: owner);

    test('anyone claims an unowned activity for themselves only', () {
      final member = rules(Role.member, null);

      expect(member.canClaim, isTrue);
      expect(member.canHandOff, isFalse);
      expect(member.allows('me'), isTrue);
      expect(member.allows('bea'), isFalse);
    });

    test('the owner hands it to anyone or nobody', () {
      final owner = rules(Role.member, 'me');

      expect(owner.canHandOff, isTrue);
      expect(owner.allows('bea'), isTrue);
      expect(owner.allows(null), isTrue);
    });

    test("a member can't take someone else's activity; an admin can", () {
      expect(rules(Role.member, 'bea').allows('me'), isFalse);
      expect(rules(Role.member, 'bea').allows(null), isFalse);
      expect(rules(Role.admin, 'bea').allows('me'), isTrue);
      expect(rules(Role.owner, 'bea').allows(null), isTrue);
    });
  });

  group('CategoryIndex', () {
    final index = CategoryIndex([
      CategoryNode.fromJson(
        categoryNodeJson(
          fieldDefs: movieFieldDefsJson(),
          subcategories: [
            categoryJson(
              id: 'sub',
              parentId: Ids.movieCategoryId,
              name: 'Horror',
              color: null,
              effectiveColor: '#7E57C2',
              icon: null,
              effectiveFieldDefs: movieFieldDefsJson(),
            ),
          ],
        ),
      ),
    ]);

    test('names, paths, inherited colours, icons and fields', () {
      expect(index.name('sub'), 'Horror');
      expect(index.path('sub'), 'Movie night › Horror');
      expect(index.color('sub'), '#7E57C2');
      expect(index.icon('sub'), 'movie');
      expect(index.fieldDefs('sub').map((d) => d.key), contains('imdb_rating'));
      expect(index.parentId('sub'), Ids.movieCategoryId);
      expect(index.fieldDefs(null), isEmpty);
      expect(index.name('missing'), isNull);
    });
  });

  test('costLabel', () {
    expect(costLabel(cost: 40, currency: 'EUR', perPerson: true), '~40 EUR pp');
    expect(costLabel(cost: 120, currency: 'RON', perPerson: false), '~120 RON');
    expect(costLabel(cost: null, currency: null, perPerson: true), isNull);
  });
}
