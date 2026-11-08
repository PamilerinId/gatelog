import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Push wake-ups, kept behind an interface so the app runs without Firebase (polling only).
abstract class PushService {
  /// The FCM registration token, or null when push is not available.
  Future<String?> token();

  /// Fires when the server sends a data message `{"type": "sync"}`.
  Stream<void> get syncRequests;

  /// Fires when Firebase rotates the token (send it with `PUT /v1/device/fcm-token`).
  Stream<String> get tokenRefresh;

  bool get available;
}

class NoPushService implements PushService {
  @override
  Future<String?> token() async => null;
  @override
  Stream<void> get syncRequests => const Stream.empty();
  @override
  Stream<String> get tokenRefresh => const Stream.empty();
  @override
  bool get available => false;
}

class FirebasePushService implements PushService {
  FirebasePushService._();

  final _sync = StreamController<void>.broadcast();

  /// Firebase is optional: with no `google-services.json` the app was built without the
  /// google-services plugin, `initializeApp` throws, and we fall back to [NoPushService].
  static Future<PushService> tryCreate() async {
    try {
      await Firebase.initializeApp();
      final s = FirebasePushService._();
      FirebaseMessaging.onMessage.listen((m) {
        if (m.data['type'] == 'sync') s._sync.add(null);
      });
      // A sync message tapped from the tray (rare: they are data-only) also wakes us.
      FirebaseMessaging.onMessageOpenedApp.listen((m) {
        if (m.data['type'] == 'sync') s._sync.add(null);
      });
      return s;
    } catch (e) {
      debugPrint('Push not configured, polling only.');
      return NoPushService();
    }
  }

  @override
  Future<String?> token() async {
    try {
      // The API sends to an FCM registration token (`message.token`), not a Firebase
      // Installation ID, so this uses the token API that firebase_messaging 17 deprecates.
      // ignore: deprecated_member_use
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<void> get syncRequests => _sync.stream;

  @override
  // ignore: deprecated_member_use
  Stream<String> get tokenRefresh => FirebaseMessaging.instance.onTokenRefresh;

  @override
  bool get available => true;
}
