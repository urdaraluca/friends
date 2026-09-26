import 'package:friends/core/invites/invite_code.dart';

/// Client-side form validators mirroring the server's rules (contract
/// sections 1.4, 4.2 and 9). The server stays the authority; these only
/// save a round trip. Lengths count Unicode code points after trimming.
abstract final class Validators {
  /// A required value of at most [max] characters after trimming.
  static String? Function(String?) required(String label, {int? max}) =>
      (value) {
        final length = (value ?? '').trim().runes.length;
        if (length == 0) return 'Enter $label.';
        if (max != null && length > max) {
          return 'Use at most $max characters.';
        }
        return null;
      };

  /// An optional value of at most [max] characters after trimming.
  static String? Function(String?) optional({required int max}) => (value) {
    final length = (value ?? '').trim().runes.length;
    return length > max ? 'Use at most $max characters.' : null;
  };

  /// A currency code: 3 letters (contract section 1.4). Lowercase letters
  /// are accepted here; send the value through [normalizeCurrency].
  static String? currency(String? value) {
    final code = normalizeCurrency(value ?? '');
    if (code.isEmpty) return 'Enter a currency.';
    return RegExp(r'^[A-Z]{3}$').hasMatch(code)
        ? null
        : 'Use a 3-letter currency code, e.g. EUR.';
  }

  /// [value] trimmed and uppercased, as the server expects currencies.
  static String normalizeCurrency(String value) => value.trim().toUpperCase();

  /// A plausible email address (the server does the real check).
  static String? email(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) return 'Enter your email.';
    if (email.runes.length > 254 ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  /// A new password: 10 to 128 characters (contract section 4.2).
  static String? newPassword(String? value) {
    final length = (value ?? '').runes.length;
    if (length == 0) return 'Enter a password.';
    if (length < 10) return 'Use at least 10 characters.';
    if (length > 128) return 'Use at most 128 characters.';
    return null;
  }

  /// An existing password: anything from 1 to 128 characters.
  static String? currentPassword(String? value) {
    final length = (value ?? '').runes.length;
    if (length == 0) return 'Enter your password.';
    if (length > 128) return 'Use at most 128 characters.';
    return null;
  }

  /// An optional invite code, in any spelling or as a `…/join/<code>` link.
  static String? optionalInviteCode(String? value) {
    if ((value ?? '').trim().isEmpty) return null;
    return InviteCode.parse(value!) == null
        ? "That doesn't look like an invite code."
        : null;
  }
}
