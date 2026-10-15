import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';
import '../theme/design_tokens.dart';
import '../widgets/ds/app_button.dart';
import '../widgets/ds/brand_logo.dart';
import '../widgets/ds/haptics.dart';
import '../widgets/ds/illustrations.dart';
import '../widgets/ds/motion.dart';

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
    (IllustrationKind.noTrips, 'onbTitle1', 'onbBody1'),
    (IllustrationKind.success, 'onbTitle2', 'onbBody2'),
    (IllustrationKind.shield, 'onbTitle3', 'onbBody3'),
  ];

  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// To the next slide. With animations off (the system setting or Low-end mode)
  /// the duration is zero, which PageController.nextPage refuses, so jump instead.
  void _next() {
    final d = DsMotion.duration(context, DsMotion.normal);
    if (d == Duration.zero) {
      _controller.jumpToPage(_page + 1);
    } else {
      _controller.nextPage(duration: d, curve: DsMotion.standard);
    }
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
    final c = context.ds;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(DsSpace.gutter, DsSpace.s2, DsSpace.s2, 0),
            child: Row(
              children: [
                const Expanded(child: Align(alignment: AlignmentDirectional.centerStart, child: BrandLockup(markSize: 32))),
                AppButton(key: const ValueKey('onbSkip'), label: tr(context, 'onbSkip'), kind: AppButtonKind.tertiary, expand: false, onPressed: _finish),
              ],
            ),
          ),
          Expanded(
            child: PageView(
              controller: _controller,
              onPageChanged: (i) {
                Haptics.tap();
                setState(() => _page = i);
              },
              children: [
                for (final (kind, title, body) in _slides)
                  LayoutBuilder(
                    builder: (context, box) => SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: DsSpace.s8),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: box.maxHeight),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const SizedBox(height: DsSpace.s6),
                          PopIn(child: IllustrationView(kind, width: 200)),
                          const SizedBox(height: DsSpace.s6),
                          FadeSlideIn(
                            delay: const Duration(milliseconds: 120),
                            child: Semantics(header: true, child: Text(tr(context, title), textAlign: TextAlign.center, style: DsType.headline.copyWith(color: c.text))),
                          ),
                          const SizedBox(height: DsSpace.s3),
                          FadeSlideIn(
                            delay: const Duration(milliseconds: 220),
                            child: Text(tr(context, body), textAlign: TextAlign.center, style: DsType.body.copyWith(height: 1.45, color: c.textMuted)),
                          ),
                          const SizedBox(height: DsSpace.s6),
                        ]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Semantics(
            label: trf(context, 'dsPageOf', {'n': _page + 1, 'm': _slides.length}),
            excludeSemantics: true,
            child: Row(key: const ValueKey('onbDots'), mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < _slides.length; i++)
                AnimatedContainer(
                  duration: DsMotion.duration(context, DsMotion.normal),
                  margin: const EdgeInsets.all(DsSpace.s1),
                  width: i == _page ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(color: i == _page ? c.primary : c.inputBorder, borderRadius: DsRadius.all(DsRadius.pill)),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(DsSpace.s5),
            child: AppButton(
              key: const ValueKey('onbNext'),
              label: tr(context, last ? 'onbStart' : 'onbNext'),
              onPressed: last ? _finish : _next,
            ),
          ),
        ]),
      ),
    );
  }
}
