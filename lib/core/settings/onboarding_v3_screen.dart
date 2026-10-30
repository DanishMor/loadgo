import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/design_tokens.dart';
import '../widgets/ds/app_button.dart';
import '../widgets/ds/brand_logo.dart';
import '../widgets/ds/illustrations.dart';
import 'onboarding_screen.dart' show OnboardingStore;

/// E26 (flag onboardingV3, needs designV3): the first-run tour. Three slides on the navy hero: pick a language and
/// see what the app is for; why the price and the trip can be trusted; why location and notifications help, told
/// before anything is asked (the system prompts still come only when a feature needs them, PermissionRationale).
/// Then [onDone] (the role pick). Skip is always there; the tour is shown once (OnboardingStore).
class OnboardingV3Screen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingV3Screen({super.key, required this.onDone});

  @override
  State<OnboardingV3Screen> createState() => _OnboardingV3ScreenState();
}

class _OnboardingV3ScreenState extends State<OnboardingV3Screen> {
  static const _count = 3;
  final _controller = PageController();
  int _page = 0;
  bool _finishing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    final d = DsMotion.duration(context, DsMotion.normal);
    if (d == Duration.zero) {
      _controller.jumpToPage(_page + 1);
    } else {
      _controller.nextPage(duration: d, curve: DsMotion.standard);
    }
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    try {
      await OnboardingStore.markSeen().timeout(const Duration(seconds: 2));
    } catch (_) {} // saving the flag must never keep the person on the tour
    if (mounted) widget.onDone();
    _finishing = false;
  }

  Widget _slide({required Widget top, required String title, required String body, List<Widget> extra = const []}) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: DsSpace.gutter, vertical: DsSpace.s4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: top),
          const SizedBox(height: DsSpace.s5),
          Semantics(header: true, child: Text(tr(context, title), textAlign: TextAlign.center, style: DsType.headline.copyWith(color: DsHero.on))),
          const SizedBox(height: DsSpace.s3),
          Text(tr(context, body), textAlign: TextAlign.center, style: DsType.body.copyWith(color: DsHero.on.withValues(alpha: 0.9))),
          ...extra,
        ]),
      );

  Widget _languages() {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: languageNotifier,
      builder: (context, current, _) => Padding(
        padding: const EdgeInsets.only(top: DsSpace.s5),
        child: Wrap(alignment: WrapAlignment.center, spacing: DsSpace.s2, runSpacing: DsSpace.s2, children: [
          for (final l in AppLanguage.values)
            ChoiceChip(
              key: ValueKey('ob3Lang_${l.name}'),
              label: Text(languageInfo[l]?.nativeName ?? l.name),
              selected: l == current,
              onSelected: (_) => setAppLanguage(l),
            ),
        ]),
      ),
    );
  }

  Widget _primer(IconData icon, String key) => Padding(
        padding: const EdgeInsets.only(top: DsSpace.s4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: DsHero.on),
          const SizedBox(width: DsSpace.s3),
          Expanded(child: Text(tr(context, key), style: DsType.body.copyWith(color: DsHero.on))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final last = _page == _count - 1;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(colors: DsHero.colors, begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: SafeArea(
          child: Column(children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                key: const ValueKey('ob3Skip'),
                style: TextButton.styleFrom(foregroundColor: DsHero.on),
                onPressed: _finish,
                child: Text(tr(context, 'onbSkip')),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _slide(top: const Column(mainAxisSize: MainAxisSize.min, children: [LogoMark(size: 72), SizedBox(height: DsSpace.s3), Wordmark(height: 28, onDark: true)]), title: 'ob3Title1', body: 'ob3Body1', extra: [_languages()]),
                  _slide(top: const IllustrationView(IllustrationKind.shield, width: 180), title: 'ob3Title2', body: 'ob3Body2'),
                  _slide(
                    top: const IllustrationView(IllustrationKind.success, width: 180),
                    title: 'ob3Title3',
                    body: 'ob3Body3',
                    extra: [_primer(Icons.location_on_outlined, 'ob3Loc'), _primer(Icons.notifications_active_outlined, 'ob3Notif')],
                  ),
                ],
              ),
            ),
            Semantics(
              label: trf(context, 'dsPageOf', {'n': _page + 1, 'm': _count}),
              child: ExcludeSemantics(
                child: Row(key: const ValueKey('ob3Dots'), mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < _count; i++)
                    Container(
                      width: i == _page ? 24 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: DsSpace.s1),
                      decoration: BoxDecoration(color: DsHero.on.withValues(alpha: i == _page ? 1 : 0.4), borderRadius: DsRadius.all(DsRadius.pill)),
                    ),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(DsSpace.s5),
              child: AppButton(key: const ValueKey('ob3Next'), label: tr(context, last ? 'onbStart' : 'onbNext'), onPressed: last ? _finish : _next),
            ),
          ]),
        ),
      ),
    );
  }
}
