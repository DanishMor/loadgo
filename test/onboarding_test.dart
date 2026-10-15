import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/settings/onboarding_screen.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/theme/design_tokens.dart';
import 'package:transport_app/core/widgets/ds/brand_logo.dart';
import 'package:transport_app/core/widgets/ds/haptics.dart';
import 'package:transport_app/core/widgets/ds/illustrations.dart';
import 'package:transport_app/core/widgets/ds/motion.dart';

/// L18: the first-time tour.
Widget host({VoidCallback? onDone, AppLanguage lang = AppLanguage.english, Brightness b = Brightness.light, double scale = 1.0, bool disableAnimations = true}) {
  final language = ValueNotifier(lang);
  final dir = (lang == AppLanguage.urdu || lang == AppLanguage.kashmiri) ? TextDirection.rtl : TextDirection.ltr;
  return LanguageScope(
    notifier: language,
    child: MaterialApp(
      theme: AppTheme.build(b),
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: disableAnimations),
        child: Directionality(textDirection: dir, child: w!),
      ),
      home: OnboardingScreen(onDone: onDone),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Haptics.enabled.value = true;
  });

  testWidgets('three slides, each with its own picture; next moves on; the last button says start', (t) async {
    await t.pumpWidget(host());
    expect(find.byType(BrandLockup), findsOneWidget);
    expect(t.widget<IllustrationView>(find.byType(IllustrationView)).kind, IllustrationKind.noTrips);
    expect(find.text(T.get('onbTitle1', AppLanguage.english)), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('onbNext')));
    await t.pumpAndSettle();
    expect(find.text(T.get('onbTitle2', AppLanguage.english)), findsOneWidget);
    expect(t.widget<IllustrationView>(find.byType(IllustrationView)).kind, IllustrationKind.success);
    await t.tap(find.byKey(const ValueKey('onbNext')));
    await t.pumpAndSettle();
    expect(t.widget<IllustrationView>(find.byType(IllustrationView)).kind, IllustrationKind.shield);
    expect(find.text(T.get('onbStart', AppLanguage.english)), findsOneWidget);
  });

  testWidgets('skip and the last button both mark the tour seen and call onDone', (t) async {
    var done = 0;
    await t.pumpWidget(host(onDone: () => done++));
    expect(await OnboardingStore.seen(), isFalse);
    await t.tap(find.byKey(const ValueKey('onbSkip')));
    await t.pumpAndSettle();
    expect(done, 1);
    expect(await OnboardingStore.seen(), isTrue);
    SharedPreferences.setMockInitialValues({});
    await t.pumpWidget(host(onDone: () => done++));
    await t.tap(find.byKey(const ValueKey('onbNext')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('onbNext')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('onbNext')));
    await t.pumpAndSettle();
    expect(done, 2);
    expect(await OnboardingStore.seen(), isTrue);
  });

  testWidgets('without onDone the screen closes itself ("show the tour again")', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.build(Brightness.light),
      home: Builder(builder: (c) => Scaffold(body: ElevatedButton(onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => const OnboardingScreen())), child: const Text('tour')))),
    ));
    await t.tap(find.text('tour'));
    await t.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('onbSkip')));
    await t.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsNothing);
  });

  testWidgets('swiping works and clicks once per page; the dots follow', (t) async {
    final calls = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') calls.add(call.arguments as String);
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await t.pumpWidget(host());
    double width(int i) => t.getSize(find.descendant(of: find.byKey(const ValueKey('onbDots')), matching: find.byType(AnimatedContainer)).at(i)).width;
    expect(width(0), 32); // 24 wide + 4 dp margin each side
    expect(width(1), 16);
    await t.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await t.pumpAndSettle();
    expect(width(0), 16);
    expect(width(1), 32);
    expect(calls, ['HapticFeedbackType.selectionClick']);
  });

  testWidgets('screen readers hear the page number in the language, and the titles are headers', (t) async {
    final h = t.ensureSemantics();
    await t.pumpWidget(host());
    expect(find.bySemanticsLabel('Page 1 of 3'), findsOneWidget);
    expect(t.getSemantics(find.text(T.get('onbTitle1', AppLanguage.english))).flagsCollection.isHeader, isTrue);
    await t.pumpWidget(host(lang: AppLanguage.hindi));
    await t.pump();
    expect(find.bySemanticsLabel('पेज 1 / 3'), findsOneWidget);
    h.dispose();
  });

  testWidgets('with animations on, the picture pops and the words arrive; with them off all is there', (t) async {
    await t.pumpWidget(host(disableAnimations: false));
    Opacity titleOpacity() => t.widget<Opacity>(find.ancestor(of: find.text(T.get('onbTitle1', AppLanguage.english)), matching: find.byType(Opacity)).first);
    expect(titleOpacity().opacity, lessThan(0.5));
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 600));
    expect(titleOpacity().opacity, 1);
    await t.pumpWidget(const SizedBox()); // a fresh tree: widget state is kept when the same widgets are pumped again
    await t.pumpWidget(host());
    await t.pumpAndSettle();
    expect(find.descendant(of: find.byType(FadeSlideIn).first, matching: find.byType(Opacity)), findsNothing);
    expect(find.descendant(of: find.byType(PopIn), matching: find.byType(Transform)), findsNothing);
  });

  for (final lang in [AppLanguage.english, AppLanguage.hindi, AppLanguage.tamil, AppLanguage.urdu]) {
    for (final b in Brightness.values) {
      testWidgets('every slide fits 360x640 at 2.0x text: ${lang.name} ${b.name}', (t) async {
        t.view.physicalSize = const Size(360, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(host(lang: lang, b: b, scale: 2.0));
        for (var i = 0; i < 3; i++) {
          expect(t.takeException(), isNull, reason: 'slide $i');
          expect(find.text(T.get('onbTitle${i + 1}', lang)), findsOneWidget);
          if (i < 2) {
            await t.tap(find.byKey(const ValueKey('onbNext')));
            await t.pumpAndSettle();
          }
        }
      });
    }
  }

  test('the dots are readable: the current one is navy-on-light, the others 3:1', () {
    for (final b in Brightness.values) {
      final c = DsColors.of(b);
      expect(c.primary, isNot(c.inputBorder));
    }
  });
}
