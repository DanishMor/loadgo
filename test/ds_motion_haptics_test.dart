import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/theme/design_tokens.dart';
import 'package:transport_app/core/widgets/ds/app_bottom_nav.dart';
import 'package:transport_app/core/widgets/ds/app_button.dart';
import 'package:transport_app/core/widgets/ds/haptics.dart';
import 'package:transport_app/core/widgets/ds/motion.dart';
import 'package:transport_app/core/widgets/ds/otp_field.dart';

/// L15 to L18 helpers: haptics and entrance animations.
Widget host(Widget child, {bool disableAnimations = false, bool lowEnd = false}) {
  final language = ValueNotifier(AppLanguage.english);
  return LanguageScope(
    notifier: language,
    child: MaterialApp(
      theme: AppTheme.build(Brightness.light, lowEnd: lowEnd),
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: disableAnimations), child: w!),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

/// Records the haptic calls the app makes.
List<String> recordHaptics(WidgetTester t) {
  final calls = <String>[];
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'HapticFeedback.vibrate') calls.add(call.arguments as String);
    return null;
  });
  addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return calls;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Haptics.enabled.value = true;
  });

  group('Haptics', () {
    testWidgets('a main button buzzes lightly, a danger button firmly, a text button with a click', (t) async {
      final calls = recordHaptics(t);
      await t.pumpWidget(host(Column(mainAxisSize: MainAxisSize.min, children: [
        AppButton(label: 'go', onPressed: () {}),
        AppButton(label: 'delete', kind: AppButtonKind.danger, onPressed: () {}),
        AppButton(label: 'later', kind: AppButtonKind.tertiary, onPressed: () {}),
      ])));
      await t.tap(find.text('go'));
      await t.tap(find.text('delete'));
      await t.tap(find.text('later'));
      expect(calls, ['HapticFeedbackType.lightImpact', 'HapticFeedbackType.heavyImpact', 'HapticFeedbackType.selectionClick']);
    });

    testWidgets('a disabled or loading button is silent, and the tap still reaches the handler once', (t) async {
      final calls = recordHaptics(t);
      var taps = 0;
      await t.pumpWidget(host(Column(mainAxisSize: MainAxisSize.min, children: [
        const AppButton(label: 'off', onPressed: null),
        AppButton(label: 'busy', loading: true, onPressed: () => taps++),
        AppButton(label: 'on', onPressed: () => taps++),
      ])));
      await t.tap(find.text('off'), warnIfMissed: false);
      await t.tap(find.byType(ElevatedButton).at(1), warnIfMissed: false);
      expect(calls, isEmpty);
      await t.tap(find.text('on'));
      expect(taps, 1);
      expect(calls.length, 1);
    });

    testWidgets('the switch turns every buzz off, and is remembered', (t) async {
      final calls = recordHaptics(t);
      await t.pumpWidget(host(AppButton(label: 'go', onPressed: () {})));
      await Haptics.set(false);
      await t.tap(find.text('go'));
      expect(calls, isEmpty);
      expect((await SharedPreferences.getInstance()).getBool('haptics_on'), isFalse);
      Haptics.enabled.value = true;
      await Haptics.load();
      expect(Haptics.enabled.value, isFalse, reason: 'load reads the saved choice');
      await Haptics.set(true);
      await t.tap(find.text('go'));
      expect(calls.length, 1);
    });

    testWidgets('a phone that cannot vibrate does not throw', (t) async {
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => throw PlatformException(code: 'nope'));
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      Haptics.press();
      Haptics.success();
      Haptics.warning();
      Haptics.tap();
      await t.pump();
      expect(t.takeException(), isNull);
    });

    testWidgets('finishing an OTP gives one click; typing fewer digits gives none', (t) async {
      final calls = recordHaptics(t);
      await t.pumpWidget(host(const OtpField(fieldKey: ValueKey('f'))));
      await t.enterText(find.byKey(const ValueKey('f')), '123');
      await t.pump();
      expect(calls, isEmpty);
      await t.enterText(find.byKey(const ValueKey('f')), '123456');
      await t.pump();
      expect(calls, ['HapticFeedbackType.selectionClick']);
    });

    testWidgets('changing tab clicks; tapping the tab you are on does not', (t) async {
      final calls = recordHaptics(t);
      await t.pumpWidget(host(AppBottomNav(items: const [
        AppNavItem(icon: Icons.home_outlined, label: 'Home'),
        AppNavItem(icon: Icons.person_outline, label: 'Me'),
      ], index: 0, onChanged: (_) {})));
      await t.tap(find.text('Home'));
      expect(calls, isEmpty);
      await t.tap(find.text('Me'));
      expect(calls, ['HapticFeedbackType.selectionClick']);
    });
  });

  group('FadeSlideIn', () {
    testWidgets('starts see-through and a little low, ends fully visible in place', (t) async {
      await t.pumpWidget(host(const FadeSlideIn(child: Text('hello'))));
      Opacity o() => t.widget<Opacity>(find.ancestor(of: find.text('hello'), matching: find.byType(Opacity)).first);
      expect(o().opacity, 0);
      await t.pump(const Duration(milliseconds: 160));
      expect(o().opacity, inExclusiveRange(0, 1));
      await t.pump(const Duration(milliseconds: 400));
      expect(o().opacity, 1);
      expect(t.widget<Transform>(find.ancestor(of: find.text('hello'), matching: find.byType(Transform)).first).transform.getTranslation().y, 0);
    });

    testWidgets('a delay holds it back until its turn', (t) async {
      await t.pumpWidget(host(const FadeSlideIn(delay: Duration(milliseconds: 300), child: Text('late'))));
      Opacity o() => t.widget<Opacity>(find.ancestor(of: find.text('late'), matching: find.byType(Opacity)).first);
      await t.pump(const Duration(milliseconds: 250));
      expect(o().opacity, 0);
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 400));
      expect(o().opacity, 1);
    });

    test('the stagger grows by 60 ms and stops at 6 steps', () {
      expect(FadeSlideIn.staggerDelay(0), Duration.zero);
      expect(FadeSlideIn.staggerDelay(1), const Duration(milliseconds: 60));
      expect(FadeSlideIn.staggerDelay(6), const Duration(milliseconds: 360));
      expect(FadeSlideIn.staggerDelay(40), const Duration(milliseconds: 360));
    });

    for (final mode in ['remove animations', 'Low-end mode']) {
      testWidgets('with $mode the child is simply there, with no animation widgets', (t) async {
        addTearDown(() => DsMotion.lowEnd = false);
        await t.pumpWidget(host(const FadeSlideIn(child: Text('now')), disableAnimations: mode == 'remove animations', lowEnd: mode == 'Low-end mode'));
        expect(find.text('now'), findsOneWidget);
        expect(find.ancestor(of: find.text('now'), matching: find.byType(Opacity)), findsNothing);
        expect(t.hasRunningAnimations, isFalse);
      });
    }

    testWidgets('leaving the screen before its turn does not throw or leak a timer', (t) async {
      await t.pumpWidget(host(const FadeSlideIn(delay: Duration(seconds: 1), child: Text('x'))));
      await t.pumpWidget(host(const SizedBox()));
      await t.pump(const Duration(seconds: 2));
      expect(t.takeException(), isNull);
    });
  });

  group('PopIn', () {
    testWidgets('grows from a smaller size to full size', (t) async {
      await t.pumpWidget(host(const PopIn(from: 0.5, child: SizedBox(width: 100, height: 100, child: Text('ok')))));
      double scale() => t.widget<Transform>(find.descendant(of: find.byType(PopIn), matching: find.byType(Transform)).first).transform.storage[0];
      expect(scale(), closeTo(0.5, 0.01));
      await t.pump(const Duration(milliseconds: 600));
      expect(scale(), closeTo(1.0, 0.01));
    });

    testWidgets('with remove animations it is full size at once', (t) async {
      await t.pumpWidget(host(const PopIn(child: Text('ok')), disableAnimations: true));
      expect(find.descendant(of: find.byType(PopIn), matching: find.byType(Transform)), findsNothing);
    });
  });
}
