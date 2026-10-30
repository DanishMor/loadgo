import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/theme/design_tokens.dart';
import 'package:transport_app/core/widgets/ds/haptics.dart';
import 'package:transport_app/core/widgets/ds/motion.dart';
import 'package:transport_app/core/widgets/ds/route_ribbon.dart';
import 'package:transport_app/core/widgets/ds/skeleton.dart';

/// E9: springs, draw-in, shimmer, success moment, hero, haptic map and the
/// per-screen animation budget.
Widget host(Widget child, {bool reduce = false}) => MaterialApp(
      theme: AppTheme.build(Brightness.light, style: ThemeStyle.signature),
      home: Builder(builder: (c) => MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: reduce), child: Scaffold(body: Center(child: child)))),
    );

void main() {
  final haptics = <String>[];
  setUp(() {
    haptics.clear();
    Haptics.enabled.value = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add('${call.arguments}');
      return null;
    });
  });

  test('the spring starts at 0, ends at 1 and overshoots at most a little', () {
    const s = SpringCurve.gentle;
    expect(s.transform(0), 0);
    expect(s.transform(1), 1);
    var peak = 0.0;
    for (var i = 1; i < 100; i++) {
      final v = s.transform(i / 100);
      if (v > peak) peak = v;
    }
    expect(peak, lessThan(1.05));
    expect(s.transform(0.5), greaterThan(0.8));
  });

  test('entrance, draw-in and success timings fit the budget', () {
    expect(FadeSlideIn.staggerDelay(100) + DsMotion.slow, lessThanOrEqualTo(MotionBudget.entrance));
    expect(RouteRibbon.drawDuration, lessThanOrEqualTo(MotionBudget.entrance));
    expect(SuccessMoment.duration, lessThanOrEqualTo(MotionBudget.success));
    expect(MotionBudget.success, lessThanOrEqualTo(const Duration(milliseconds: 600)));
  });

  test('repeating animations live only in the allowed components, one each', () {
    // A looping animation costs battery on every frame; each one is a reviewed decision.
    const allowed = {'skeleton.dart'};
    final found = <String, int>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final n = RegExp(r'\.repeat\(').allMatches(f.readAsStringSync()).length;
      if (n > 0) found[f.uri.pathSegments.last] = n;
    }
    for (final e in found.entries) {
      expect(allowed, contains(e.key), reason: '${e.key} starts a repeating animation; add it to the budget review first');
      expect(e.value, lessThanOrEqualTo(MotionBudget.looping), reason: e.key);
    }
  });

  test('the haptic map: light for errors, heavy only for SOS', () {
    Haptics.on(HapticEvent.select);
    Haptics.on(HapticEvent.confirm);
    Haptics.on(HapticEvent.error);
    Haptics.on(HapticEvent.sos);
    expect(haptics, ['HapticFeedbackType.selectionClick', 'HapticFeedbackType.mediumImpact', 'HapticFeedbackType.lightImpact', 'HapticFeedbackType.heavyImpact']);
    haptics.clear();
    Haptics.enabled.value = false;
    Haptics.on(HapticEvent.sos);
    expect(haptics, isEmpty, reason: 'touch feedback switched off');
  });

  RouteRibbonPainter painter(WidgetTester t) => t.widget<CustomPaint>(find.descendant(of: find.byType(RouteRibbon), matching: find.byType(CustomPaint))).painter! as RouteRibbonPainter;

  testWidgets('the route line draws in once, or is complete at once with reduced motion', (t) async {
    await t.pumpWidget(host(const SizedBox(width: 300, child: RouteRibbon(from: 'Pune', to: 'Nashik', distanceKm: 210, drawIn: true))));
    expect(painter(t).reveal, 0);
    await t.pump(RouteRibbon.drawDuration ~/ 2);
    expect(painter(t).reveal, inExclusiveRange(0, 1));
    await t.pumpAndSettle();
    expect(painter(t).reveal, 1);
    await t.pumpWidget(host(const SizedBox(width: 300, child: RouteRibbon(from: 'A', to: 'B', drawIn: true)), reduce: true));
    expect(painter(t).reveal, 1);
    final p = painter(t);
    expect(p.shouldRepaint(RouteRibbonPainter(line: p.line, dot: p.dot, pin: p.pin, truck: p.truck, reveal: 0.5)), isTrue);
  });

  testWidgets('skeleton boxes shimmer, and are flat grey when motion is reduced', (t) async {
    BoxDecoration deco() => t.widget<Container>(find.descendant(of: find.byType(SkeletonBox), matching: find.byType(Container))).decoration! as BoxDecoration;
    await t.pumpWidget(host(const Skeleton(child: SkeletonBox(width: 120))));
    await t.pump(const Duration(milliseconds: 100));
    final g1 = deco().gradient! as LinearGradient;
    await t.pump(const Duration(milliseconds: 300));
    final g2 = deco().gradient! as LinearGradient;
    expect(g1.begin, isNot(g2.begin), reason: 'the highlight moves');
    await t.pumpWidget(host(const Skeleton(child: SkeletonBox(width: 120)), reduce: true));
    await t.pump();
    expect(deco().gradient, isNull);
    expect(deco().color, DsColors.signature.chip);
  });

  testWidgets('the success moment pops once, gives one haptic and is announced', (t) async {
    final h = t.ensureSemantics();
    await t.pumpWidget(host(const SuccessMoment(label: 'Booking confirmed')));
    expect(find.bySemanticsLabel('Booking confirmed'), findsOneWidget);
    await t.pumpAndSettle();
    expect(haptics, ['HapticFeedbackType.mediumImpact']);
    await t.pumpWidget(host(const SuccessMoment(key: ValueKey('still'), label: 'Done'), reduce: true));
    expect(find.descendant(of: find.byType(PopIn), matching: find.byType(AnimatedBuilder)), findsNothing);
    h.dispose();
  });

  testWidgets('the hero flies normally and stays put with reduced motion', (t) async {
    await t.pumpWidget(host(const DsHeroTag(tag: 'truck', child: Icon(Icons.local_shipping))));
    expect(find.byType(Hero), findsOneWidget);
    await t.pumpWidget(host(const DsHeroTag(tag: 'truck', child: Icon(Icons.local_shipping)), reduce: true));
    expect(find.byType(Hero), findsNothing);
  });
}
