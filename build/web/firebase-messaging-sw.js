importScripts('https://www.gstatic.com/firebasejs/12.14.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.14.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyBErSK32BUayrbPgnvoSiZgVj9Z59KdqFg',
  authDomain: 'ptc-mvp.firebaseapp.com',
  projectId: 'ptc-mvp',
  storageBucket: 'ptc-mvp.firebasestorage.app',
  messagingSenderId: '240255196807',
  appId: '1:240255196807:web:c463b91f36c0be829c6222',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const data = payload.data || {};
  self.registration.showNotification(data.title || 'Check Chassis', {
    body: data.body || 'A chassis needs client confirmation.',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: data.notificationId || 'chassis-check',
    renotify: true,
    requireInteraction: true,
    data: {url: data.url || '/'},
  });
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(clients.openWindow(event.notification.data?.url || '/'));
});
