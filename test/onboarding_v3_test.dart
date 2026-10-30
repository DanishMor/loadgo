import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/settings/onboarding_screen.dart';
import 'package:transport_app/core/settings/onboarding_v3_screen.dart';
import 'package:transport_app/core/theme/app_theme.dart';

/// E26: the first-run tour v3.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => null);
    languageNotifier.value = AppLanguage.english;
  });
  tearDown(() => languageNotifier.value = AppLanguage.english);

  Widget host(Widget child, {Brightness b = Brightness.light, double scale = 1, bool noMotion = false}) => LanguageScope(
        notifier: languageNotifier,
        child: MaterialApp(
          theme: AppTheme.build(b, style: ThemeStyle.signature),
          builder: (c, w) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: noMotion),
            child: Directionality(textDirection: languageNotifier.value.textDirection, child: w!),
          ),
          home: child,
        ),
      );

  testWidgets('language pick changes the words at once; three slides, then the role pick; seen is remembered', (t) async {
    var done = 0;
    await t.pumpWidget(host(OnboardingV3Screen(onDone: () => done++)));
    await t.pumpAndSettle();
    expect(find.text(T.get('ob3Title1', AppLanguage.english)), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('ob3Lang_hindi')));
    await t.pumpAndSettle();
    expect(find.text(T.get('ob3Title1', AppLanguage.hindi)), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('ob3Next')));
    await t.pumpAndSettle();
    expect(find.text(T.get('ob3Title2', AppLanguage.hindi)), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('ob3Next')));
    await t.pumpAndSettle();
    expect(find.text(T.get('ob3Loc', AppLanguage.hindi)), findsOneWidget);
    expect(find.text(T.get('ob3Notif', AppLanguage.hindi)), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('ob3Next')));
    await t.pumpAndSettle();
    expect(done, 1);
    expect(await OnboardingStore.seen(), isTrue);
  });

  testWidgets('skip leaves at once; with reduced motion Next jumps', (t) async {
    var done = 0;
    await t.pumpWidget(host(OnboardingV3Screen(onDone: () => done++), noMotion: true));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('ob3Next')));
    await t.pump();
    expect(find.text(T.get('ob3Title2', AppLanguage.english)), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('ob3Skip')));
    await t.pumpAndSettle();
    expect(done, 1);
  });

  for (final (lang, b) in [(AppLanguage.hindi, Brightness.light), (AppLanguage.urdu, Brightness.dark), (AppLanguage.tamil, Brightness.dark)]) {
    testWidgets('no overflow at 320 dp and 2.0x on every slide: ${lang.name} ${b.name}', (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      languageNotifier.value = lang;
      await t.pumpWidget(host(OnboardingV3Screen(onDone: () {}), b: b, scale: 2, noMotion: true));
      await t.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        expect(t.takeException(), isNull, reason: 'slide $i');
        if (i < 2) {
          await t.tap(find.byKey(const ValueKey('ob3Next')));
          await t.pumpAndSettle();
        }
      }
    });
  }
}
