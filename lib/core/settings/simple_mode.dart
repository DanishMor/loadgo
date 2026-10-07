import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';
import '../widgets/common.dart';

/// Driver Simple Mode: big buttons, icons and very little text. Saved on the
/// device (shared_preferences); off until the driver chooses it.
class SimpleMode {
  SimpleMode._();

  static const _key = 'driver_simple_mode';
  static const _askedKey = 'driver_simple_mode_asked';

  static final ValueNotifier<bool> notifier = ValueNotifier(false);
  static bool get isOn => notifier.value;

  /// Reads the saved choice (call once at start). No storage means off.
  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      notifier.value = p.getBool(_key) ?? false;
    } catch (_) {
      notifier.value = false;
    }
  }

  static Future<void> set(bool on) async {
    notifier.value = on;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_key, on);
    } catch (_) {}
  }

  /// True when the first-start question was not answered yet. Without
  /// storage it counts as answered, so nobody is asked on every start.
  static Future<bool> shouldAsk() async {
    try {
      final p = await SharedPreferences.getInstance();
      return !(p.getBool(_askedKey) ?? false);
    } catch (_) {
      return false;
    }
  }

  static Future<void> markAsked() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_askedKey, true);
    } catch (_) {}
  }

  @visibleForTesting
  static void reset() => notifier.value = false;
}

/// Settings switch for Simple Mode.
class SimpleModeSwitch extends StatelessWidget {
  const SimpleModeSwitch({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: SimpleMode.notifier,
        builder: (context, on, _) => SwitchListTile(
          key: const ValueKey('simpleModeSwitch'),
          secondary: const Icon(Icons.accessibility_new_rounded),
          title: Text(tr(context, 'simpleModeTitle')),
          subtitle: Text(tr(context, 'simpleModeSub')),
          value: on,
          onChanged: SimpleMode.set,
        ),
      );
}

/// First-start question on the driver home. Not a dialog, so nothing is
/// blocked; it disappears after either answer.
class SimpleModePrompt extends StatefulWidget {
  const SimpleModePrompt({super.key});

  @override
  State<SimpleModePrompt> createState() => _SimpleModePromptState();
}

class _SimpleModePromptState extends State<SimpleModePrompt> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    SimpleMode.shouldAsk().then((v) {
      if (mounted && v && !SimpleMode.isOn) setState(() => _show = true);
    });
  }

  Future<void> _answer(bool yes) async {
    setState(() => _show = false);
    await SimpleMode.markAsked();
    if (yes) await SimpleMode.set(true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: AppCard(
        child: Column(
          key: const ValueKey('simpleModePrompt'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.accessibility_new_rounded, size: 28),
              const SizedBox(width: 10),
              Expanded(child: Text(tr(context, 'simpleModeAsk'), style: const TextStyle(fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: FilledButton(key: const ValueKey('simpleModeYes'), onPressed: () => _answer(true), child: Text(tr(context, 'simpleModeYes')))),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton(key: const ValueKey('simpleModeNo'), onPressed: () => _answer(false), child: Text(tr(context, 'simpleModeNo')))),
            ]),
          ],
        ),
      ),
    );
  }
}
