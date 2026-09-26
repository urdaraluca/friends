import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/invites/invite_code.dart';

void main() {
  group('InviteCode', () {
    // The same cases as backend/tests/api/test_invites.py and contract 4.7.
    const cases = {
      'abcd-efgh-jk': 'ABCDEFGHJK',
      ' abcd efgh ik ': 'ABCDEFGH1K',
      '0O1IL23456': '0011123456',
      'abcd-efgh-ik': 'ABCDEFGH1K',
      ' abcde fghjk ': 'ABCDEFGHJK',
      'ABCDEFGHJ': null, // too short
      'ABCDEFGHJU': null, // U is not in the alphabet
    };

    for (final MapEntry(key: raw, value: expected) in cases.entries) {
      test('parses "$raw" as $expected', () {
        expect(InviteCode.parse(raw), expected);
      });
    }

    test('normalize strips separators, uppercases and maps I/L/O', () {
      expect(InviteCode.normalize('il-o\t x'), '110X');
    });

    test('accepts a pasted join link', () {
      expect(
        InviteCode.parse('https://friends.example.com/join/abcde-fghjk'),
        'ABCDEFGHJK',
      );
      expect(
        InviteCode.parse('  http://localhost:5000/join/ABCDEFGHJK?utm=x '),
        'ABCDEFGHJK',
      );
      expect(InviteCode.parse('https://x.test/join/nope'), isNull);
      expect(
        InviteCode.parse('https://x.test/join/ABCDE%2DFGHJK'),
        'ABCDEFGHJK',
      );
      expect(InviteCode.parse('https://x.test/join/%E0%A4%A'), isNull);
    });

    test('isValid and format', () {
      expect(InviteCode.isValid('ABCDEFGHJK'), isTrue);
      expect(InviteCode.isValid('abcdefghjk'), isFalse);
      expect(InviteCode.format('ABCDEFGHJK'), 'ABCDE-FGHJK');
      expect(InviteCode.format('SHORT'), 'SHORT');
    });
  });
}
