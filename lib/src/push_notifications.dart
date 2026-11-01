import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'firestore_service.dart';

class PushNotifications {
  static const _vapidKey = String.fromEnvironment('FIREBASE_VAPID_KEY');

  static Future<String> enableForUser({
    required FirestoreService service,
    required String uid,
  }) async {
    if (!kIsWeb) {
      return 'Browser push notifications are available in the web app.';
    }
    if (_vapidKey.isEmpty) {
      return 'Add the Firebase web push key and restart the app to enable push.';
    }

    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return 'Notifications are blocked in browser settings.';
    }

    final token = await FirebaseMessaging.instance.getToken(vapidKey: _vapidKey);
    if (token == null || token.isEmpty) {
      return 'Could not register this browser for notifications.';
    }
    await service.savePushToken(uid: uid, token: token);
    return 'Browser notifications are enabled on this device.';
  }
}