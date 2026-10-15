import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import 'breadcrumbs.dart';
import 'error_log_service.dart';

/// An error with its text cleaned by [Redactor] (the type name is kept).
class RedactedError implements Exception {
  final String type;
  final String message;
  RedactedError(Object error)
      : type = error.runtimeType.toString(),
        message = Redactor.safe(error);

  @override
  String toString() => '$type: $message';
}

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
      debugPrint('Uncaught error: ${Redactor.safe(error)}');
      record(error, stack, fatal: true);
      return true;
    };
  }

  static void record(Object error, StackTrace? stack, {bool fatal = false}) {
    // A sample also goes to the admin health screen (no personal data).
    ErrorLogService.logSampled(error, stack, fatal: fatal);
    if (!_active) return;
    try {
      FirebaseCrashlytics.instance.log(Breadcrumbs.trail());
      // The message is cleaned first: an error text can carry a phone number, UPI id or path with ids.
      FirebaseCrashlytics.instance.recordError(RedactedError(error), stack, fatal: fatal);
    } catch (_) {}
  }

  @visibleForTesting
  static void reset() => _active = false;
}
