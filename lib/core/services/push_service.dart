import 'breadcrumbs.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend.dart';
import 'device_service.dart';
import '../features/features.dart';
import '../permissions/permission_rationale.dart';
import 'features_service.dart';

/// Registers this device for push notifications by storing its FCM token on
/// the signed-in user's profile. The actual push is sent by the Cloud
/// Function in `functions/` whenever a document is added to `notifications`.
class PushService {
  PushService._();

  static StreamSubscription<String>? _refreshSub; // ignore: cancel_subscriptions (one for the life of the app, started once)

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
      debugPrint('Push registration skipped: ${Redactor.safe(e)}');
    }
  }

  /// With the `pushNotifications` switch on, a plain-words explanation comes
  /// first (Play Store policy: say why before asking); without it, the old
  /// behaviour: ask straight away. "Not now" asks again next time.
  static Future<void> ensure(BuildContext context) async {
    if (FeaturesService.isOn(FeatureKey.pushNotifications) && !await PermissionRationale.ask(context, RationaleKind.notifications)) return;
    await register();
  }

  static const _askedKey = 'push_asked_day';

  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  /// After sign-in (with the `pushNotifications` switch on): if the person has
  /// not yet seen the explanation, show it - at most once a day, a few seconds
  /// after the screen settled. If it was accepted before, just make sure the
  /// token is saved. Never throws.
  static Future<void> askAfterSignIn(GlobalKey<NavigatorState> navigatorKey, {Duration wait = const Duration(seconds: 5)}) async {
    try {
      if (!FeaturesService.isOn(FeatureKey.pushNotifications)) return;
      if (await PermissionRationale.seen(RationaleKind.notifications)) {
        unawaited(register());
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final today = now().toIso8601String().substring(0, 10);
      if (prefs.getString(_askedKey) == today) return;
      await Future<void>.delayed(wait);
      final context = navigatorKey.currentContext;
      if (context == null || !context.mounted || Backend.uid == null) return;
      await prefs.setString(_askedKey, today);
      if (context.mounted) await ensure(context);
    } catch (_) {}
  }

  /// Keeps [token] on the signed-in user's profile and on this device's record
  /// (users/{uid}/devices/{id}.fcmToken, one token per device, so a revoked or
  /// signed-out device stops getting messages). The server reads both.
  static Future<void> saveToken(String token) async {
    final uid = Backend.uid;
    if (uid == null) return;
    await Backend.db.collection('users').doc(uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
    }, SetOptions(merge: true));
    try {
      await Backend.db.collection('users').doc(uid).collection('devices').doc(await DeviceService.deviceId()).update({
        'fcmToken': token,
        'fcmUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // No device record yet (it is made at sign-in) or offline: the profile list still has the token.
    }
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
      try {
        await Backend.db.collection('users').doc(uid).collection('devices').doc(await DeviceService.deviceId()).update({'fcmToken': FieldValue.delete()});
      } catch (_) {}
    } catch (e) {
      debugPrint('Push unregister skipped: ${Redactor.safe(e)}');
    }
  }
}
