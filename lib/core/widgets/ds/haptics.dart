import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small vibrations for the actions that matter: pressing a main button,
/// moving between tabs, finishing a code, a confirmed step, a warning. One
/// switch (Settings > Touch feedback) turns all of them off; it is kept on the
/// phone and is on by default. Every call is safe: on a phone without a
/// vibration motor, or in a test, nothing happens and nothing throws.
class Haptics {
  Haptics._();

  static const _key = 'haptics_on';
  static final ValueNotifier<bool> enabled = ValueNotifier(true);

  static Future<void> load() async {
    try {
      enabled.value = (await SharedPreferences.getInstance()).getBool(_key) ?? true;
    } catch (_) {
      enabled.value = true;
    }
  }

  static Future<void> set(bool on) async {
    enabled.value = on;
    try {
      await (await SharedPreferences.getInstance()).setBool(_key, on);
    } catch (_) {}
  }

  static void _go(Future<void> Function() f) {
    if (!enabled.value) return;
    try {
      f().catchError((Object _) {});
    } catch (_) {}
  }

  /// A tap on a tab, a chip, a row: the lightest click.
  static void tap() => _go(HapticFeedback.selectionClick);

  /// Pressing a main button.
  static void press() => _go(HapticFeedback.lightImpact);

  /// A step finished well: code complete, booking confirmed, delivered.
  static void success() => _go(HapticFeedback.mediumImpact);

  /// Something to stop and think about: delete, cancel, an error.
  static void warning() => _go(HapticFeedback.heavyImpact);
}
