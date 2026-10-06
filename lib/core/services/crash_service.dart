import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Crash reporting (Crashlytics). Every call is a safe no-op when Firebase is
/// not available (tests, debug builds, a missing google-services file).
class CrashService {
  CrashService._();

  static bool _active = false;
  static bool get active => _active;

  /// Wires [FlutterError.onError] and [PlatformDispatcher.onError]. Errors
  /// are always logged locally; they go to Crashlytics only in release.
  static Future<void> init() async {
    try {
      _active = !kDebugMode;
      if (_active) await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
    } catch (_) {
      _active = false;
    }
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      record(details.exception, details.stack, fatal: true);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('Uncaught error: $error\n$stack');
      record(error, stack, fatal: true);
      return true;
    };
  }

  static void record(Object error, StackTrace? stack, {bool fatal = false}) {
    if (!_active) return;
    try {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: fatal);
    } catch (_) {}
  }

  @visibleForTesting
  static void reset() => _active = false;
}
