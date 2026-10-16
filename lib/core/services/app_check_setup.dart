import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

/// G15: Firebase App Check on the phone. App Check lets the servers (Firestore, Storage, our functions) tell the real
/// app from a copy or a script. It starts in MONITOR mode: the app only sends its proof; nothing refuses a request
/// until the owner switches enforcement on in the Firebase Console, one product at a time (docs/APP_CHECK.md).
///
/// It is built in but asleep: it starts only when the build is made with `--dart-define=APP_CHECK=on`, which the owner
/// does after registering the app with Play Integrity in the Console. Without it nothing changes for anyone.
class AppCheckSetup {
  AppCheckSetup._();

  static const mode = String.fromEnvironment('APP_CHECK', defaultValue: 'off');

  /// Which provider this build would use: 'debug' (development builds: the token printed in the log is added to the
  /// Console by the developer), 'playIntegrity' (release builds on Android) or 'none' (everything else, the web admin
  /// included: it needs a reCAPTCHA site key, see the docs).
  static String providerFor({required bool debug, required bool web, required TargetPlatform platform}) {
    if (web || platform != TargetPlatform.android) return 'none';
    return debug ? 'debug' : 'playIntegrity';
  }

  @visibleForTesting
  static Future<void> Function(String provider) activator = _activate;

  static Future<void> _activate(String provider) async {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: provider == 'debug' ? const AndroidDebugProvider() : const AndroidPlayIntegrityProvider(),
    );
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
  }

  /// Starts App Check when the build asked for it. Never throws and never holds the app back.
  /// Returns the provider name used, or null when it did not start.
  static Future<String?> start({String? buildMode, bool? debug, bool? web, TargetPlatform? platform}) async {
    if ((buildMode ?? mode) != 'on') return null;
    final p = providerFor(debug: debug ?? kDebugMode, web: web ?? kIsWeb, platform: platform ?? defaultTargetPlatform);
    if (p == 'none') return null;
    try {
      await activator(p);
      return p;
    } catch (_) {
      return null;
    }
  }
}
