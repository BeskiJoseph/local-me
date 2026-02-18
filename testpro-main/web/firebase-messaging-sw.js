importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-messaging-compat.js');

firebase.initializeApp({
    apiKey: 'AIzaSyBzrLKKXfHl5Lfzyt7tE-pQ6d82D-_-67Y',
    appId: '1:869861670780:web:785ca317636c7db41a6ef9',
    messagingSenderId: '869861670780',
    projectId: 'testpro-73a93',
    authDomain: 'testpro-73a93.firebaseapp.com',
    storageBucket: 'testpro-73a93.firebasestorage.app',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
    console.log('[firebase-messaging-sw.js] Received background message ', payload);
    const notificationTitle = payload.notification.title;
    const notificationOptions = {
        body: payload.notification.body,
        icon: '/favicon.png'
    };

    self.registration.showNotification(notificationTitle, notificationOptions);
});
