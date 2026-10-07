import 'package:flutter/material.dart';

import '../services/user_service.dart';

/// Screens that core/ and the role folders need to reach but must not
/// import (they live in auth/). main.dart registers them at start-up.
class AppRoutes {
  AppRoutes._();

  /// The first screen of the signed-out app (role selection).
  static WidgetBuilder? roleSelection;

  /// The Admin panel row for the Profile tab; null (hidden) until registered.
  /// The row itself checks `admins/{uid}` before it shows anything.
  static WidgetBuilder? adminEntry;

  /// Opens a booking for its role: the driver's trip screen or the customer's
  /// tracking screen. Registered by main.dart.
  static void Function(BuildContext context, String bookingId, {required bool isDriver})? openBooking;

  /// Opens a load by id (a shared link or a search hit); drivers get the
  /// Accept button. Registered by main.dart.
  static void Function(BuildContext context, String loadId, {required bool isDriver})? openLoad;

  /// Starts Post Load from a place (customers). Registered by main.dart.
  static void Function(BuildContext context, {String? pickup, String? drop})? openPostLoad;

  /// Signs out and replaces the whole navigation stack with [roleSelection].
  static Future<void> logout(BuildContext context) async {
    await UserService.logout();
    final build = roleSelection;
    if (!context.mounted || build == null) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: build), (route) => false);
  }
}
