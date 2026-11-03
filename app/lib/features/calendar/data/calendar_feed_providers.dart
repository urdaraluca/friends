import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/api_providers.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'calendar_feed_providers.g.dart';

/// My webcal subscription (`/me/calendar-feed`, contract section 5.10): a
/// secret URL other calendar apps subscribe to. Its URLs are null while it
/// is off.
@riverpod
class CalendarFeedController extends _$CalendarFeedController {
  @override
  Future<CalendarFeed> build() {
    ref.watch(currentUserIdProvider);
    final client = ref.watch(usersClientProvider);
    return apiCall(client.getMyCalendarFeed);
  }

  /// `POST`: turns the feed on, or replaces its URL (the old one stops
  /// working).
  Future<void> reset() async {
    final client = ref.read(usersClientProvider);
    state = AsyncData(await apiCall(client.resetMyCalendarFeed));
  }

  /// `DELETE`: turns the feed off.
  Future<void> disable() async {
    final client = ref.read(usersClientProvider);
    await apiCall(client.disableMyCalendarFeed);
    state = const AsyncData(CalendarFeed(url: null, webcalUrl: null));
  }
}
