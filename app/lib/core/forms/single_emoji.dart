import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// A group's emoji is exactly one emoji (contract section 9): one grapheme
/// cluster, so a ZWJ sequence (👩‍💻), a flag (🇷🇴), a keycap (1️⃣) or a skin
/// tone (👍🏽) counts as one.
abstract final class SingleEmoji {
  // The server's rule: the cluster's first code point is a symbol (Unicode
  // category So), or it is a keycap sequence.
  static final _emoji = RegExp(r'^(?:\p{So}|[0-9#*]️?⃣)', unicode: true);

  /// Whether [value] (trimmed) is a single emoji.
  static bool isValid(String value) {
    final characters = value.trim().characters;
    return characters.length == 1 && _emoji.hasMatch(characters.first);
  }

  /// The first emoji-sized character of [value], for a stored value from
  /// before the one-emoji rule ("🎲🎉" becomes "🎲").
  static String? first(String? value) {
    final characters = value?.trim().characters;
    if (characters == null || characters.isEmpty) return value;
    return characters.first;
  }
}

/// Keeps a text field to one character (grapheme): typing or pasting
/// replaces what was there with the first character entered.
class SingleCharacterFormatter extends TextInputFormatter {
  const new();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.characters.length <= 1) return newValue;
    final start = oldValue.selection.isValid ? oldValue.selection.start : 0;
    final end = newValue.selection.isValid ? newValue.selection.end : -1;
    final inserted = start >= 0 && end >= start && end <= text.length
        ? text.substring(start, end).characters
        : Characters.empty;
    final kept = inserted.isNotEmpty ? inserted.first : text.characters.last;
    return TextEditingValue(
      text: kept,
      selection: TextSelection.collapsed(offset: kept.length),
    );
  }
}
