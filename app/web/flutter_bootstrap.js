{{flutter_js}}
{{flutter_build_config}}

// No serviceWorkerSettings: Flutter's deprecated flutter_service_worker.js would take over the
// app's scope and unregister itself, which also deletes the Web Push subscription held by
// push_sw.js (contract section 18.6). push_sw.js is the only service worker.
_flutter.loader.load();
