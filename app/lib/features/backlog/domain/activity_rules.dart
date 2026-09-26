import 'package:friends/core/api/date_only.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/features/groups/domain/group_permissions.dart';
import 'package:material_ui/material_ui.dart';

/// Labels and colours of the activity statuses.
extension ActivityStatusLabel on ActivityStatus {
  String get label => switch (this) {
    ActivityStatus.idea => 'Idea',
    ActivityStatus.planning => 'Planning',
    ActivityStatus.scheduled => 'Scheduled',
    ActivityStatus.done => 'Done',
    ActivityStatus.dropped => 'Dropped',
    ActivityStatus.$unknown => 'Other',
  };

  IconData get icon => switch (this) {
    ActivityStatus.idea => Icons.lightbulb_outline,
    ActivityStatus.planning => Icons.edit_calendar_outlined,
    ActivityStatus.scheduled => Icons.event_available_outlined,
    ActivityStatus.done => Icons.check_circle_outline,
    ActivityStatus.dropped => Icons.block,
    ActivityStatus.$unknown => Icons.help_outline,
  };

  /// Done and dropped are the archive.
  bool get isArchived =>
      this == ActivityStatus.done || this == ActivityStatus.dropped;
}

/// Who may change an activity's owner (contract section 7.2): admins and
/// owners always; the current owner may hand it to anyone or to nobody;
/// anyone may claim an unowned activity for themselves.
@immutable
class OwnerRules {
  const new({
    required this.myRole,
    required this.myUserId,
    required this.ownerId,
  });

  final Role myRole;
  final String myUserId;

  /// The activity's current owner, or null when unowned.
  final String? ownerId;

  bool get _isAdmin => myRole.isAdminOrOwner;

  /// "Claim it": the activity is unowned.
  bool get canClaim => ownerId == null;

  /// Pick any member (or nobody) as the owner.
  bool get canHandOff => _isAdmin || ownerId == myUserId;

  /// Whether the owner may become [newOwnerId] (null = unowned).
  bool allows(String? newOwnerId) {
    if (newOwnerId == ownerId) return true;
    if (canHandOff) return true;
    return ownerId == null && newOwnerId == myUserId;
  }
}

/// A complete `PUT /activities/{id}` body that keeps everything of
/// [activity] (its `version` included), for a one-field change such as the
/// owner. [ownerId] replaces the owner when given (`() => null` = nobody).
ActivityUpdate activityUpdateFrom(
  Activity activity, {
  String? Function()? ownerId,
}) {
  return ActivityUpdate(
    title: activity.title,
    version: activity.version,
    costPerPerson: activity.costPerPerson,
    description: activity.description,
    notes: activity.notes,
    categoryId: activity.categoryId,
    ownerId: ownerId == null ? activity.owner?.id : ownerId(),
    dueDate: DateOnly.fromNullable(activity.dueDate),
    estimatedCost: activity.estimatedCost,
    currency: activity.currency,
    locationName: activity.locationName,
    address: activity.address,
    links: activity.links,
    attributes: activity.attributes,
  );
}

/// "~40 EUR pp", "120 RON", or null without a cost.
String? costLabel({
  required int? cost,
  required String? currency,
  required bool perPerson,
}) {
  if (cost == null) return null;
  final amount = '~$cost${currency == null ? '' : ' $currency'}';
  return perPerson ? '$amount pp' : amount;
}
