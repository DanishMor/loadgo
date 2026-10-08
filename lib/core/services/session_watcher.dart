import 'dart:async';

/// Notices when the signed-in session ends without the person asking for it
/// (the token was revoked, the account was disabled or deleted elsewhere) and
/// calls [onExpired] once, so the app can take them back to the first screen
/// with "Please sign in again" instead of leaving screens that only fail
/// (MASTER-5 Task 17).
///
/// A sign-out the app does itself (Logout, account deletion) calls
/// [SessionWatcher.expectSignOut] first and is not reported.
class SessionWatcher {
  static bool _expected = false;

  /// Call right before a sign-out or an Auth user deletion made by the app.
  static void expectSignOut() => _expected = true;

  final void Function() onExpired;
  StreamSubscription<bool>? _sub;
  bool _wasSignedIn = false;

  SessionWatcher(Stream<bool> signedIn, {required this.onExpired}) {
    _sub = signedIn.listen((now) {
      if (now) {
        _expected = false;
      } else if (_wasSignedIn && !_expected) {
        onExpired();
      } else {
        _expected = false;
      }
      _wasSignedIn = now;
    });
  }

  Future<void> dispose() async => _sub?.cancel();
}
