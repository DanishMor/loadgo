import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'backend.dart';

/// Registers this device for push notifications by storing its FCM token on
/// the signed-in user's profile. The actual push is sent by the Cloud
/// Function in `functions/` whenever a document is added to `notifications`.
class PushService {
  PushService._();

  static StreamSubscription<String>? _refreshSub;

  /// Ask for permission and save the token. Safe to call repeatedly; never
  /// throws (push is an enhancement, the in-app inbox still works).
  static Future<void> register() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await messaging.getToken();
      if (token != null) await saveToken(token);
      _refreshSub ??= messaging.onTokenRefresh.listen(saveToken);
    } catch (e) {
      debugPrint('Push registration skipped: $e');
    }
  }

  /// Adds [token] to users/{uid}.fcmTokens (one entry per device).
  static Future<void> saveToken(String token) async {
    final uid = Backend.uid;
    if (uid == null) return;
    await Backend.db.collection('users').doc(uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
    }, SetOptions(merge: true));
  }

  /// Removes this device's token (call on sign-out so the next user on the
  /// same phone doesn't receive the previous user's pushes).
  static Future<void> unregister() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      final uid = Backend.uid;
      if (token == null || uid == null) return;
      await Backend.db.collection('users').doc(uid).set({
        'fcmTokens': FieldValue.arrayRemove([token]),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Push unregister skipped: $e');
    }
  }
}
