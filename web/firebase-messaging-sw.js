importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyC-Pq2ZPvCcp5rsSnkJfMLXxrS5JJfod98',
  appId: '1:919602851188:web:2068356a638e28caf61021',
  messagingSenderId: '919602851188',
  projectId: 'bhromon-ff801',
  authDomain: 'app.bhromon.fun',
  storageBucket: 'bhromon-ff801.firebasestorage.app',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage(function(payload) {
  const data = (payload && payload.data) || {};
  const action = data.action || '';
  const callId = data.callId || '';

  // Dismiss any ringing call notification instead of popping up a blank alert.
  if (action === 'end_call') {
    if (callId && self.registration.getNotifications) {
      return self.registration
        .getNotifications({ tag: 'call_' + callId })
        .then(function(list) {
          list.forEach(function(n) { n.close(); });
        });
    }
    return Promise.resolve();
  }

  const notificationTitle = payload.notification
    ? payload.notification.title
    : (data.title || 'Bhromon');
  const notificationBody = payload.notification
    ? payload.notification.body
    : (data.body || '');
  if (!payload.notification && !data.title && !data.body && action !== 'call') {
    return Promise.resolve();
  }

  const notificationOptions = {
    body: notificationBody,
    icon: '/icons/Icon-192.png',
    data: data,
  };
  if (action === 'call' && callId) {
    notificationOptions.tag = 'call_' + callId;
    notificationOptions.requireInteraction = true;
    notificationOptions.renotify = true;
  }

  return self.registration.showNotification(notificationTitle, notificationOptions);
});

self.addEventListener('notificationclick', function(event) {
  const data = (event.notification && event.notification.data) || {};
  event.notification.close();

  const targetUrl = (function() {
    if (data.action === 'call' && data.callId) {
      const params = new URLSearchParams();
      if (data.callerId) params.set('callerId', data.callerId);
      if (data.callerName) params.set('callerName', data.callerName);
      if (data.isVideo) params.set('isVideo', data.isVideo);
      const q = params.toString();
      return '/#/call/' + encodeURIComponent(data.callId) + (q ? ('?' + q) : '');
    }
    return '/';
  })();

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function(clientList) {
      for (let i = 0; i < clientList.length; i++) {
        const client = clientList[i];
        if ('focus' in client) {
          if (targetUrl !== '/' && 'navigate' in client) {
            return client.navigate(targetUrl).then(function(c) { return (c || client).focus(); });
          }
          return client.focus();
        }
      }
      if (self.clients.openWindow) {
        return self.clients.openWindow(targetUrl);
      }
    })
  );
});
