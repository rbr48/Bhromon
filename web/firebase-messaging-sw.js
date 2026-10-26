importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyC-Pq2ZPvCcp5rsSnkJfMLXxrS5JJfod98',
  appId: '1:919602851188:web:2068356a638e28caf61021',
  messagingSenderId: '919602851188',
  projectId: 'bhromon-ff801',
  authDomain: 'bhromon-ff801.firebaseapp.com',
  storageBucket: 'bhromon-ff801.firebasestorage.app',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage(function(payload) {
  const notificationTitle = payload.notification ? payload.notification.title : 'Bhromon';
  const notificationOptions = {
    body: payload.notification ? payload.notification.body : '',
    icon: '/icons/Icon-192.png'
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});
