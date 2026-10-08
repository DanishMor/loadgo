import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';

enum RationaleKind { location, notifications, microphone, callMicrophone }

/// A plain-words explanation shown once before the system permission prompt
/// (Play Store policy: say why before asking). "Continue" is remembered on the
/// device and the system prompt follows; "Not now" asks again next time.
class PermissionRationale {
  PermissionRationale._();

  static String _key(RationaleKind k) => 'rationale_seen_${k.name}';

  /// Translation keys: (title, body, icon).
  static (String, String, IconData) textFor(RationaleKind k) => switch (k) {
        RationaleKind.location => ('rationaleLocationTitle', 'rationaleLocationBody', Icons.location_on_outlined),
        RationaleKind.notifications => ('rationaleNotifTitle', 'rationaleNotifBody', Icons.notifications_active_outlined),
        RationaleKind.microphone => ('rationaleMicTitle', 'rationaleMicBody', Icons.mic_none_rounded),
        // Task 68: the in-app voice call.
        RationaleKind.callMicrophone => ('pcMicTitle', 'pcMicBody', Icons.call_rounded),
      };

  static Future<bool> seen(RationaleKind k) async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_key(k)) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _mark(RationaleKind k) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_key(k), true);
    } catch (_) {}
  }

  /// True when the system prompt may follow: the explanation was already
  /// accepted before, or the user accepts it now.
  static Future<bool> ask(BuildContext context, RationaleKind k) async {
    if (await seen(k)) return true;
    if (!context.mounted) return false;
    final (title, body, icon) = textFor(k);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: Icon(icon),
        title: Text(tr(c, title)),
        content: Text(tr(c, body)),
        actions: [
          TextButton(key: const ValueKey('rationaleNo'), onPressed: () => Navigator.pop(c, false), child: Text(tr(c, 'rationaleNotNow'))),
          FilledButton(key: const ValueKey('rationaleYes'), onPressed: () => Navigator.pop(c, true), child: Text(tr(c, 'rationaleContinue'))),
        ],
      ),
    );
    if (ok != true) return false;
    await _mark(k);
    return true;
  }
}
