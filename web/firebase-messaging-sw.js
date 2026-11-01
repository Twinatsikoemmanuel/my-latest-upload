importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyBdRms-jAY7QBASwaPohEheB76G1TJmCtY',
  authDomain: 'dabtmateapp.firebaseapp.com',
  projectId: 'dabtmateapp',
  storageBucket: 'dabtmateapp.firebasestorage.app',
  messagingSenderId: '133709490525',
  appId: '1:133709490525:web:6e5ab6c11a85c384dfa0b4',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const notification = payload.notification || {};
  self.registration.showNotification(notification.title || 'DebtMate', {
    body: notification.body || 'You have a new notification.',
    icon: '/icons/Icon-192.png',
    data: payload.data || {},
  });
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windows) => {
      const appWindow = windows.find((window) => window.url.startsWith(self.location.origin));
      if (appWindow) return appWindow.focus();
      return clients.openWindow('/');
    }),
  );
});