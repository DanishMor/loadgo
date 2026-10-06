import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Thin Analytics wrapper. Only screen and event names plus short coded
/// parameters; never names, phone numbers, addresses or amounts.
class AnalyticsEvents {
  AnalyticsEvents._();

  static bool enabled = !kDebugMode;

  static const screenView = 'screen_view';
  static const loadPosted = 'load_posted';
  static const offerSent = 'offer_sent';
  static const bookingDone = 'booking_done';

  static final RegExp _name = RegExp(r'^[a-z][a-z0-9_]{0,39}$');

  /// Analytics rules: letter first, then letters, digits or `_`, max 40.
  static bool validName(String s) => _name.hasMatch(s);

  /// Keeps only short string/number params with valid keys.
  static Map<String, Object> cleanParams(Map<String, Object?>? p) {
    final out = <String, Object>{};
    p?.forEach((k, v) {
      if (!validName(k)) return;
      if (v is num) out[k] = v;
      if (v is String) out[k] = v.length > 36 ? v.substring(0, 36) : v;
    });
    return out;
  }

  static Future<void> log(String name, {Map<String, Object?>? params}) async {
    if (!enabled || !validName(name)) return;
    try {
      await FirebaseAnalytics.instance.logEvent(name: name, parameters: cleanParams(params));
    } catch (_) {}
  }

  static Future<void> screen(String screenName) => log(screenView, params: {'screen_name': screenName});
}
