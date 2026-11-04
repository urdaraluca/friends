import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/api_providers.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'notification_providers.g.dart';

/// Which notification emails I get (`/me/notifications`, contract section
/// 18.4).
@riverpod
class NotificationSettingsController extends _$NotificationSettingsController {
  @override
  Future<NotificationSettings> build() {
    ref.watch(currentUserIdProvider);
    return apiCall(ref.watch(usersClientProvider).getMyNotifications);
  }

  /// `PUT`: saves [settings], showing them right away; on failure the
  /// previous ones come back and the error is rethrown.
  Future<void> save(NotificationSettings settings) async {
    final previous = state;
    state = AsyncData(settings);
    try {
      state = AsyncData(
        await apiCall(
          () => ref
              .read(usersClientProvider)
              .updateMyNotifications(body: settings),
        ),
      );
    } on ApiException {
      state = previous;
      rethrow;
    }
  }
}
