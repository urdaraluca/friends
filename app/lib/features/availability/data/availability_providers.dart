import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/api_providers.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/features/availability/domain/month_days.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'availability_providers.g.dart';

/// My answers for the grid of [month] (`GET /me/availability`, [gridRange]).
@riverpod
Future<MyAvailability> myAvailability(Ref ref, DateTime month) {
  ref.watch(currentUserIdProvider);
  final range = gridRange(month);
  final client = ref.watch(usersClientProvider);
  return apiCall(
    () => client.getMyAvailability(from: range.from, to: range.to),
  );
}

/// A group's heatmap for the grid of [month]
/// (`GET /groups/{id}/availability`, [gridRange]).
@riverpod
Future<GroupAvailability> groupAvailability(
  Ref ref,
  String groupId,
  DateTime month,
) {
  ref.watch(currentUserIdProvider);
  final range = gridRange(month);
  final client = ref.watch(availabilityClientProvider);
  return apiCall(
    () => client.getGroupAvailability(
      groupId: groupId,
      from: range.from,
      to: range.to,
    ),
  );
}

/// Saves my answers (contract section 13).
@Riverpod(keepAlive: true)
class AvailabilityController extends _$AvailabilityController {
  @override
  void build() {}

  /// `PUT /me/availability`: replaces my answers in the grid of [month]
  /// ([gridRange]) by [entries].
  Future<MyAvailability> saveMonth(
    DateTime month,
    List<AvailabilityEntryWrite> entries,
  ) async {
    final range = gridRange(month);
    final saved = await apiCall(
      () => ref
          .read(usersClientProvider)
          .updateMyAvailability(
            body: MyAvailabilityUpdate(
              fromDate: range.from,
              toDate: range.to,
              entries: entries,
            ),
          ),
    );
    ref
      ..invalidate(myAvailabilityProvider)
      ..invalidate(groupAvailabilityProvider);
    return saved;
  }
}
