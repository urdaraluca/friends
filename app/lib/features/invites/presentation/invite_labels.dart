import 'package:friends/core/api/generated/export.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:intl/intl.dart';

/// "Active", "Expired", "Revoked" or "Used up".
String inviteStatusLabel(InviteStatus status) => switch (status) {
  InviteStatus.valid => currentL10n.inviteActive,
  InviteStatus.expired => currentL10n.inviteExpiredLabel,
  InviteStatus.revoked => currentL10n.inviteRevokedLabel,
  InviteStatus.exhausted => currentL10n.inviteUsedUp,
  InviteStatus.$unknown => currentL10n.inviteUnavailable,
};

/// Why an invite in [status] can't be used, or null when it can.
String? inviteUnusableReason(InviteStatus status) => switch (status) {
  InviteStatus.valid => null,
  InviteStatus.expired => currentL10n.inviteExpiredReason,
  InviteStatus.revoked => currentL10n.inviteRevokedReason,
  InviteStatus.exhausted => currentL10n.inviteExhaustedReason,
  InviteStatus.$unknown => currentL10n.inviteUnusableReason,
};

/// "Expires Oct 3, 2026 5:30 PM" (local time), "Expired …", or "Never
/// expires".
String inviteExpiryLabel(DateTime? expiresAt, {DateTime? now}) {
  if (expiresAt == null) return currentL10n.neverExpires;
  final local = expiresAt.toLocal();
  final formatted = DateFormat.yMMMd().add_jm().format(local);
  return local.isAfter(now ?? DateTime.now())
      ? currentL10n.expiresOn(formatted)
      : currentL10n.expiredOn(formatted);
}
