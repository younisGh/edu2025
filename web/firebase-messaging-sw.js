/* eslint-disable no-undef */
// Firebase Messaging Service Worker (compat build)
// This file must be located at the site root as: /firebase-messaging-sw.js
// It enables background notifications for Firebase Cloud Messaging on web.

importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

// IMPORTANT: Keep this config in sync with your web/firebase-config.js
firebase.initializeApp({
  apiKey: "AIzaSyBfzcrx6QgC8w69oVIfbZmI5vYGKXX0m_k",
  authDomain: "educational-platform-16729.firebaseapp.com",
  projectId: "educational-platform-16729",
  storageBucket: "educational-platform-16729.firebasestorage.app",
  messagingSenderId: "101585046920",
  appId: "1:101585046920:web:282abf34ac1dd7d17cbe3d",
});

const messaging = firebase.messaging();

// Optional: handle background messages to show a notification
messaging.onBackgroundMessage((payload) => {
  const title = payload?.notification?.title || 'إشعار جديد';
  const options = {
    body: payload?.notification?.body || '',
    icon: '/favicon.png',
    data: payload?.data || {},
  };
  self.registration.showNotification(title, options);
});
