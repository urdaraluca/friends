import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:friends/core/config/document_base.dart';
import 'package:friends/core/push/web_push.dart';

@JS('Notification')
external JSObject? get _notificationClass;

@JS('Notification.permission')
external String get _permission;

@JS('Notification.requestPermission')
external JSPromise<JSString> _requestPermission();

@JS('navigator.serviceWorker')
external _ServiceWorkerContainer? get _serviceWorker;

@JS('PushManager')
external JSObject? get _pushManagerClass;

extension type _ServiceWorkerContainer(JSObject _) implements JSObject {
  external JSPromise<_Registration> register(String url, JSObject options);
}

extension type _Registration(JSObject _) implements JSObject {
  external _PushManager get pushManager;
}

extension type _PushManager(JSObject _) implements JSObject {
  external JSPromise<_Subscription?> getSubscription();
  external JSPromise<_Subscription> subscribe(JSObject options);
}

extension type _Subscription(JSObject _) implements JSObject {
  external String get endpoint;
  external JSObject toJSON();
  external JSPromise<JSBoolean> unsubscribe();
}

bool supported() =>
    _notificationClass != null &&
    _serviceWorker != null &&
    _pushManagerClass != null;

String permission() => supported() ? _permission : 'unsupported';

Future<_Registration> _registration() {
  final base = documentBaseUri();
  final options = JSObject()..['scope'] = base.path.toJS;
  return _serviceWorker!
      .register(base.resolve('push_sw.js').toString(), options)
      .toDart;
}

BrowserPushSubscription _read(_Subscription subscription) {
  final json = jsonDecode(
    (globalContext['JSON']! as JSObject)
        .callMethod<JSString>('stringify'.toJS, subscription.toJSON())
        .toDart,
  ) as Map<String, dynamic>;
  final keys = json['keys'] as Map<String, dynamic>;
  return BrowserPushSubscription(
    endpoint: subscription.endpoint,
    p256dh: keys['p256dh'] as String,
    auth: keys['auth'] as String,
  );
}

Future<BrowserPushSubscription?> current() async {
  if (!supported()) return null;
  final registration = await _registration();
  final subscription = await registration.pushManager.getSubscription().toDart;
  return subscription == null ? null : _read(subscription);
}

Future<BrowserPushSubscription?> subscribe(String vapidPublicKey) async {
  if (!supported()) return null;
  if (_permission != 'granted') {
    final answer = (await _requestPermission().toDart).toDart;
    if (answer != 'granted') return null;
  }
  final registration = await _registration();
  final key = base64Url.decode(base64Url.normalize(vapidPublicKey));
  final options = JSObject()
    ..['userVisibleOnly'] = true.toJS
    ..['applicationServerKey'] = Uint8List.fromList(key).toJS;
  final subscription = await registration.pushManager.subscribe(options).toDart;
  return _read(subscription);
}

Future<String?> unsubscribe() async {
  if (!supported()) return null;
  final registration = await _registration();
  final subscription = await registration.pushManager.getSubscription().toDart;
  if (subscription == null) return null;
  final endpoint = subscription.endpoint;
  await subscription.unsubscribe().toDart;
  return endpoint;
}
