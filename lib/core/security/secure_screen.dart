import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/features.dart';
import '../services/features_service.dart';

/// Blocks screenshots and screen recording (Android `FLAG_SECURE`) while a
/// sensitive screen is open (F4). Only in release builds and only when the
/// `secureScreens` feature flag is on, so debugging and demos are unaffected.
/// Several sensitive widgets can be open at once: the flag is cleared when the
/// last one closes.
class SecureScreen {
  SecureScreen._();

  static const channel = MethodChannel('loadgo/secure_screen');

  static int _holders = 0;
  static bool _applied = false;

  /// Tests replace this; the app asks "release build, Android, flag on".
  @visibleForTesting
  static bool Function() enabledCheck = _defaultEnabled;

  static bool _defaultEnabled() =>
      kReleaseMode && defaultTargetPlatform == TargetPlatform.android && FeaturesService.isOn(FeatureKey.secureScreens);

  static Future<void> acquire() async {
    _holders++;
    await _sync();
  }

  static Future<void> release() async {
    if (_holders > 0) _holders--;
    await _sync();
  }

  static Future<void> _sync() async {
    final want = _holders > 0 && enabledCheck();
    if (want == _applied) return;
    _applied = want;
    try {
      await channel.invokeMethod<void>('set', want);
    } catch (_) {
      _applied = !want; // no native side (web, tests, old build): never break the screen
    }
  }

  @visibleForTesting
  static void reset() {
    _holders = 0;
    _applied = false;
    enabledCheck = _defaultEnabled;
  }
}

/// Wrap a sensitive screen (or card) in this. It shows [child] unchanged.
class SecureScope extends StatefulWidget {
  final Widget child;
  const SecureScope({super.key, required this.child});

  @override
  State<SecureScope> createState() => _SecureScopeState();
}

class _SecureScopeState extends State<SecureScope> {
  @override
  void initState() {
    super.initState();
    SecureScreen.acquire();
  }

  @override
  void dispose() {
    SecureScreen.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
