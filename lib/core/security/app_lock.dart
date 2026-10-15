import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/features.dart';
import '../l10n/l10n.dart';
import '../services/features_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/ds/app_button.dart';

/// Asks the phone for the fingerprint, face or screen lock. The real one needs
/// the `local_auth` plugin and a test on a real phone (docs/BLOCKED.md), so
/// until it is plugged in [AppLock.authenticator] says "not available" and the
/// switch in Settings stays off.
abstract class AppLockAuthenticator {
  /// The phone has a fingerprint, face or screen lock set up.
  Future<bool> isAvailable();

  /// Shows the phone's own prompt. True only when the person passed it.
  Future<bool> authenticate(String reason);
}

class UnavailableAppLockAuthenticator implements AppLockAuthenticator {
  const UnavailableAppLockAuthenticator();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<bool> authenticate(String reason) async => false;
}

/// F11: an optional lock on the money screens (flag `appLock`, default OFF; the
/// person also turns it on in Settings). After a successful unlock the screens
/// stay open for [grace]; after that they ask again.
class AppLock {
  AppLock._();

  static const _key = 'app_lock_on';
  static const grace = Duration(minutes: 1);

  static AppLockAuthenticator authenticator = const UnavailableAppLockAuthenticator();
  static final ValueNotifier<bool> enabled = ValueNotifier(false);
  static DateTime? _unlockedAt;

  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  static Future<void> load() async {
    try {
      enabled.value = (await SharedPreferences.getInstance()).getBool(_key) ?? false;
    } catch (_) {
      enabled.value = false;
    }
  }

  /// Turning it on needs the phone to be able to check; turning it off is always possible.
  static Future<bool> set(bool on) async {
    if (on && !await authenticator.isAvailable()) return false;
    enabled.value = on;
    _unlockedAt = null;
    try {
      await (await SharedPreferences.getInstance()).setBool(_key, on);
    } catch (_) {}
    return true;
  }

  /// True when the money screens must be locked right now.
  static bool get locked {
    if (!FeaturesService.isOn(FeatureKey.appLock) || !enabled.value) return false;
    final at = _unlockedAt;
    return at == null || now().difference(at) >= grace;
  }

  /// Asks the phone. On success the screens stay open for [grace].
  static Future<bool> unlock(String reason) async {
    bool ok;
    try {
      ok = await authenticator.authenticate(reason);
    } catch (_) {
      ok = false;
    }
    if (ok) _unlockedAt = now();
    return ok;
  }

  @visibleForTesting
  static void reset() {
    enabled.value = false;
    _unlockedAt = null;
    authenticator = const UnavailableAppLockAuthenticator();
    now = DateTime.now;
  }
}

/// Wrap a money screen in this. With the lock off it shows [child] as it is;
/// with the lock on it shows an unlock button first.
class AppLockGate extends StatefulWidget {
  final Widget child;
  const AppLockGate({super.key, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> {
  bool _asked = false;
  bool _busy = false;

  Future<void> _unlock() async {
    final reason = tr(context, 'appLockUnlock');
    setState(() => _busy = true);
    final ok = await AppLock.unlock(reason);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _asked = true;
      if (!ok) return;
    });
  }

  @override
  void initState() {
    super.initState();
    // Ask straight away when the screen opens locked.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && AppLock.locked && !_asked) _unlock();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!AppLock.locked) return widget.child;
    final c = context.ds;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(DsSpace.s8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock_outline_rounded, size: 56, color: c.primary),
              const SizedBox(height: DsSpace.s4),
              Text(tr(context, 'appLockUnlock'), textAlign: TextAlign.center, style: DsType.title.copyWith(color: c.text)),
              const SizedBox(height: DsSpace.s6),
              AppButton(
                key: const ValueKey('appLockUnlockButton'),
                label: tr(context, 'appLockUnlock'),
                icon: Icons.fingerprint_rounded,
                loading: _busy,
                onPressed: _unlock,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
