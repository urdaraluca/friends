import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/api_providers.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/push/web_push.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'push_controller.g.dart';

/// Push in this browser (contract section 18.6), the main notification
/// channel.
class PushState {
  const new({
    required this.supported,
    required this.permission,
    required this.enabled,
  });

  /// The browser can do push and the server has a VAPID key.
  final bool supported;
  final PushPermission permission;

  /// This browser is subscribed for the signed-in user.
  final bool enabled;
}

@Riverpod(keepAlive: true)
class PushController extends _$PushController {
  WebPush get _push => ref.read(webPushProvider);

  NotificationsClient get _client => ref.read(notificationsClientProvider);

  String? _serverKey;

  /// Also re-registers an existing subscription for whoever is signed in,
  /// so the server knows this browser after a sign-in.
  @override
  Future<PushState> build() async {
    final userId = ref.watch(currentUserIdProvider);
    final push = ref.watch(webPushProvider);
    if (userId == null || !push.supported) return _off(push);
    final client = ref.watch(notificationsClientProvider);
    final config = await apiCall(client.getPushConfig);
    _serverKey = config.publicKey;
    if (_serverKey == null) return _off(push);
    final current = push.permission == PushPermission.granted
        ? await push.current()
        : null;
    if (current != null) await _save(current);
    return PushState(
      supported: true,
      permission: push.permission,
      enabled: current != null,
    );
  }

  PushState _off(WebPush push) =>
      PushState(supported: false, permission: push.permission, enabled: false);

  Future<void> _save(BrowserPushSubscription subscription) => apiCall(
    () => _client.savePushSubscription(
      body: PushSubscriptionWrite(
        endpoint: subscription.endpoint,
        keys: PushKeys(p256dh: subscription.p256dh, auth: subscription.auth),
      ),
    ),
  );

  /// Asks the browser and turns push on. False when permission is refused.
  Future<bool> enable() async {
    final key = _serverKey;
    if (key == null) return false;
    final subscription = await _push.subscribe(key);
    if (subscription != null) await _save(subscription);
    state = AsyncData(
      PushState(
        supported: true,
        permission: _push.permission,
        enabled: subscription != null,
      ),
    );
    return subscription != null;
  }

  /// Turns push off in this browser.
  Future<void> disable() async {
    final endpoint = await _push.unsubscribe();
    if (endpoint != null) {
      await apiCall(() => _client.deletePushSubscription(endpoint: endpoint));
    }
    state = AsyncData(
      PushState(supported: true, permission: _push.permission, enabled: false),
    );
  }
}

/// Whether the "turn on notifications" card was dismissed on this device.
@Riverpod(keepAlive: true)
class PushPromptDismissed extends _$PushPromptDismissed {
  static const _key = 'friends.push_prompt_dismissed';

  @override
  Future<bool> build() async {
    try {
      return await SharedPreferencesAsync().getBool(_key) ?? false;
    } on Object {
      return false;
    }
  }

  Future<void> dismiss() async {
    state = const AsyncData(true);
    try {
      await SharedPreferencesAsync().setBool(_key, true);
    } on Object {
      // Best effort: it comes back next time.
    }
  }
}
