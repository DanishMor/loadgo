import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../features/features.dart';
import '../navigation/app_routes.dart';
import '../services/backend.dart';
import '../services/breadcrumbs.dart';
import '../services/features_service.dart';
import 'notifications_screen.dart';
import 'push_target.dart';

/// Opens the right screen when a push message is tapped (F24): the booking
/// (also for chat and LR messages: the chat and the LR sit on that screen),
/// the earnings screen, a load, or the in-app notification list. Everything is
/// best effort: a damaged message, a signed-out person or a missing hook ends
/// in the notification list or in nothing, never in a crash.
class PushRouter {
  PushRouter._();

  static bool _started = false;
  static StreamSubscription<RemoteMessage>? _sub;
  static Map<String, dynamic>? _waiting;

  /// Where the tap goes for a person who is a driver (or transporter) or a customer.
  /// Pure and testable: [PushTarget] says what, this says how.
  static void openTarget(BuildContext context, PushTarget target, {required bool isDriver}) {
    final id = target.id;
    switch (target.screen) {
      case PushScreen.booking || PushScreen.chat || PushScreen.lr:
        final open = AppRoutes.openBooking;
        if (id != null && open != null) {
          open(context, id, isDriver: isDriver);
          return;
        }
      case PushScreen.load:
        final open = AppRoutes.openLoad;
        if (id != null && open != null) {
          open(context, id, isDriver: isDriver);
          return;
        }
      case PushScreen.wallet:
        final open = AppRoutes.openWallet;
        if (open != null) {
          open(context, isDriver: isDriver);
          return;
        }
      case PushScreen.notifications:
        break;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => NotificationsScreen(
        isDriver: isDriver,
        onOpenBooking: (id) => AppRoutes.openBooking?.call(context, id, isDriver: isDriver),
      ),
    ));
  }

  /// Call once from main() after Firebase started. Does nothing while the
  /// `pushNotifications` switch is off.
  static Future<void> start(GlobalKey<NavigatorState> navigatorKey) async {
    if (_started) return;
    _started = true;
    try {
      final messaging = FirebaseMessaging.instance;
      final first = await messaging.getInitialMessage();
      if (first != null) _waiting = first.data;
      _sub = FirebaseMessaging.onMessageOpenedApp.listen((m) => unawaited(open(navigatorKey, m.data)));
      if (_waiting != null) {
        final data = _waiting!;
        _waiting = null;
        // Wait for the first frame: the app was started by the tap.
        WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(open(navigatorKey, data)));
      }
    } catch (e) {
      _started = false; // a later call may still work
      Breadcrumbs.add('push router off');
    }
  }

  static Future<void> open(GlobalKey<NavigatorState> navigatorKey, Map<String, dynamic> data) async {
    if (!FeaturesService.isOn(FeatureKey.pushNotifications)) return;
    try {
      final context = navigatorKey.currentContext;
      if (context == null || Backend.uid == null) return;
      final target = PushTarget.fromData(data);
      final role = (await Backend.db.collection('users').doc(Backend.uid).get()).data()?['selectedRole'];
      if (!context.mounted) return;
      openTarget(context, target, isDriver: role == 'driver' || role == 'fleet');
    } catch (_) {
      // A broken tap must never take the app down.
    }
  }

  static void stop() {
    _sub?.cancel();
    _sub = null;
    _started = false;
  }
}
