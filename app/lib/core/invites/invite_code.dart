/// Invite codes, normalized exactly like the server (contract section 4.7).
abstract final class InviteCode {
  /// Codes are 10 characters of Crockford base32 (no I, L, O or U).
  static final _valid = RegExp(r'^[0-9A-HJKMNP-TV-Z]{10}$');
  static final _separators = RegExp(r'[\s-]');
  static final _joinUrl = RegExp(r'/join/([^/?#\s]+)');

  /// Strips whitespace and `-`, uppercases, and maps `I`/`L` to `1` and `O`
  /// to `0`. The result may still be invalid; see [isValid].
  static String normalize(String raw) => raw
      .replaceAll(_separators, '')
      .toUpperCase()
      .replaceAll('I', '1')
      .replaceAll('L', '1')
      .replaceAll('O', '0');

  /// Whether [normalized] is a well-formed code.
  static bool isValid(String normalized) => _valid.hasMatch(normalized);

  /// The normalized code in [input], which may be a code in any spelling or
  /// a pasted `…/join/<code>` link. Returns null when there is no valid code.
  static String? parse(String input) {
    final trimmed = input.trim();
    final fromUrl = _joinUrl.firstMatch(trimmed)?.group(1);
    final raw = fromUrl == null ? trimmed : _decodeSegment(fromUrl);
    if (raw == null) return null;
    final code = normalize(raw);
    return isValid(code) ? code : null;
  }

  /// Percent-decodes a path segment, or null when its escapes are malformed.
  static String? _decodeSegment(String segment) {
    try {
      return Uri.tryParse('/$segment')?.pathSegments.firstOrNull;
    } on FormatException {
      return null;
    }
  }

  /// Display form `XXXXX-XXXXX` of a normalized code.
  static String format(String code) =>
      code.length == 10 ? '${code.substring(0, 5)}-${code.substring(5)}' : code;
}
