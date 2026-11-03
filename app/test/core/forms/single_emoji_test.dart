import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/forms/single_emoji.dart';

void main() {
  group('SingleEmoji.isValid', () {
    test('one emoji, sequences included', () {
      for (final emoji in [
        '🎬',
        '❤️',
        '👩‍💻',
        '👍🏽',
        '🇷🇴',
        '1️⃣',
        '🏳️‍🌈',
      ]) {
        expect(SingleEmoji.isValid(emoji), isTrue, reason: emoji);
      }
    });

    test('not several, and not letters or digits', () {
      for (final value in ['🎲🎉', '🇷🇴🇮🇹', 'A', '1', ':)', '🎬 x', '']) {
        expect(SingleEmoji.isValid(value), isFalse, reason: value);
      }
    });
  });

  test('SingleEmoji.first keeps the first character', () {
    expect(SingleEmoji.first('🎲🎉'), '🎲');
    expect(SingleEmoji.first('👩‍💻x'), '👩‍💻');
    expect(SingleEmoji.first(null), isNull);
    expect(SingleEmoji.first(''), '');
  });

  group('SingleCharacterFormatter', () {
    const formatter = SingleCharacterFormatter();

    TextEditingValue typed(String old, String now) =>
        formatter.formatEditUpdate(
          TextEditingValue(
            text: old,
            selection: TextSelection.collapsed(offset: old.length),
          ),
          TextEditingValue(
            text: now,
            selection: TextSelection.collapsed(offset: now.length),
          ),
        );

    test('keeps one character as is', () {
      expect(typed('', '👩‍💻').text, '👩‍💻');
    });

    test('what is typed replaces what was there', () {
      expect(typed('🎬', '🎬🍿').text, '🍿');
      expect(typed('🎬', '🎬🍿').selection.baseOffset, '🍿'.length);
    });

    test('a pasted run keeps its first character', () {
      expect(typed('', '🎲🎉').text, '🎲');
    });
  });
}
