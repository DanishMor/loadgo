import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:local_auth/local_auth.dart';

import 'app_lock.dart';

/// The real fingerprint / face / screen-lock prompt, through the `local_auth`
/// plugin. Each call is wrapped so a missing sensor or a plugin error never
/// throws into the screen: it answers "not available" or "not unlocked".
class LocalAuthAppLockAuthenticator implements AppLockAuthenticator {
  final LocalAuthentication _auth;
  LocalAuthAppLockAuthenticator([LocalAuthentication? auth]) : _auth = auth ?? LocalAuthentication();

  /// Plugs the real prompt in on phones. The web build keeps the "not available" one.
  static void install() {
    if (kIsWeb) return;
    AppLock.authenticator = LocalAuthAppLockAuthenticator();
  }

  @override
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      // Screen lock (PIN, pattern) is allowed too, so a person without a
      // fingerprint is not locked out of their own earnings.
      return await _auth.authenticate(localizedReason: reason);
    } catch (_) {
      return false;
    }
  }
}
