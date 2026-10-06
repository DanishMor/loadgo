import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';

/// Remembers on this device that the first-time slides were shown.
class OnboardingStore {
  OnboardingStore._();

  static const _key = 'onboarding_seen';

  static Future<bool> seen() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_key) ?? false;
    } catch (_) {
      return true; // storage unavailable: never block the app on the tour
    }
  }

  static Future<void> markSeen() async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_key, true);
    } catch (_) {}
  }
}

/// Three first-time slides. [onDone] runs after the last slide or Skip; when
/// it is null the screen just pops (used for "show the tour again").
class OnboardingScreen extends StatefulWidget {
  final VoidCallback? onDone;

  const OnboardingScreen({super.key, this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _slides = [
    (Icons.local_shipping_rounded, 'onbTitle1', 'onbBody1'),
    (Icons.verified_user_rounded, 'onbTitle2', 'onbBody2'),
    (Icons.lock_person_rounded, 'onbTitle3', 'onbBody3'),
  ];

  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await OnboardingStore.markSeen();
    if (!mounted) return;
    if (widget.onDone != null) {
      widget.onDone!();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _slides.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(key: const ValueKey('onbSkip'), onPressed: _finish, child: Text(tr(context, 'onbSkip'))),
          ),
          Expanded(
            child: PageView(
              controller: _controller,
              onPageChanged: (i) => setState(() => _page = i),
              children: [
                for (final (icon, title, body) in _slides)
                  SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const SizedBox(height: 40),
                      Icon(icon, size: 96, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 28),
                      Text(tr(context, title), textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 12),
                      Text(tr(context, body), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.4)),
                    ]),
                  ),
              ],
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < _slides.length; i++)
              Container(
                margin: const EdgeInsets.all(4),
                width: i == _page ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == _page ? Theme.of(context).colorScheme.primary : Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.all(20),
            child: FilledButton(
              key: const ValueKey('onbNext'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: last
                  ? _finish
                  : () => _controller.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
              child: Text(tr(context, last ? 'onbStart' : 'onbNext')),
            ),
          ),
        ]),
      ),
    );
  }
}
