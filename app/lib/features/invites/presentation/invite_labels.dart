import 'package:friends/core/api/generated/export.dart';
import 'package:intl/intl.dart';

/// "Active", "Expired", "Revoked" or "Used up".
String inviteStatusLabel(InviteStatus status) => switch (status) {
  InviteStatus.valid => 'Active',
  InviteStatus.expired => 'Expired',
  InviteStatus.revoked => 'Revoked',
  InviteStatus.exhausted => 'Used up',
  InviteStatus.$unknown => 'Unavailable',
};

/// Why an invite in [status] can't be used, or null when it can.
String? inviteUnusableReason(InviteStatus status) => switch (status) {
  InviteStatus.valid => null,
  InviteStatus.expired => 'This invite has expired. Ask for a new one.',
  InviteStatus.revoked =>
    'This invite was revoked, so it no longer works. Ask for a new one.',
  InviteStatus.exhausted => 'This invite has been used up. Ask for a new one.',
  InviteStatus.$unknown => "This invite can't be used. Ask for a new one.",
};

/// "Expires Oct 3, 2026 5:30 PM" (local time), "Expired …", or "Never
/// expires".
String inviteExpiryLabel(DateTime? expiresAt, {DateTime? now}) {
  if (expiresAt == null) return 'Never expires';
  final local = expiresAt.toLocal();
  final formatted = DateFormat.yMMMd().add_jm().format(local);
  return local.isAfter(now ?? DateTime.now())
      ? 'Expires $formatted'
      : 'Expired $formatted';
}
