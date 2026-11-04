// Web Push (contract section 18.6): shows what the server sends and opens its link on a tap.
// Registered by the app (lib/core/push/web_push_web.dart) at the app's base path.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (_) {
    data = { body: event.data ? event.data.text() : '' };
  }
  const icon = new URL('icons/Icon-192.png', self.registration.scope).href;
  event.waitUntil(
    self.registration.showNotification(data.title || 'Friends', {
      body: data.body || '',
      tag: data.tag,
      icon,
      badge: icon,
      data: { url: data.url || self.registration.scope },
    }),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = event.notification.data && event.notification.data.url;
  const target = url && url.startsWith(self.registration.scope) ? url : self.registration.scope;
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windows) => {
      for (const client of windows) {
        if (client.url.startsWith(self.registration.scope) && 'focus' in client) {
          return client.focus().then((focused) => (focused.navigate ? focused.navigate(target) : focused));
        }
      }
      return self.clients.openWindow(target);
    }),
  );
});
