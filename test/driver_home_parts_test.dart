import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/adapters/connect_adapters.dart';
import 'package:transport_app/core/adapters/maps_adapter.dart';
import 'package:transport_app/core/home/driver_home_logic.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/theme/design_tokens.dart';
import 'package:transport_app/driver/v3/driver_home_parts.dart';

Booking delivered(String id, DateTime at) => Booking.fromMap(id, {
      'status': 'delivered',
      'driverId': 'd1',
      'timeline': {'delivered': Timestamp.fromDate(at)},
    });

/// E22a: driver home pieces: level, streak, papers, goal, radar pulse, ring, demand strip.
void main() {
  final now = DateTime(2027, 5, 20, 15);

  group('logic', () {
    test('levels by delivered trips, with progress to the next', () {
      expect(DriverLevel.of(0), DriverLevel.starter);
      expect(DriverLevel.of(9), DriverLevel.starter);
      expect(DriverLevel.of(10), DriverLevel.regular);
      expect(DriverLevel.of(199), DriverLevel.pro);
      expect(DriverLevel.of(5000), DriverLevel.star);
      expect(DriverLevel.starter.progress(5), 0.5);
      expect(DriverLevel.star.next, isNull);
      expect(DriverLevel.star.progress(300), 1);
    });

    test('streak counts days in a row ending today or yesterday', () {
      DateTime d(int ago) => DateTime(2027, 5, 20 - ago, 10);
      expect(deliveryStreak([delivered('a', d(0)), delivered('b', d(1)), delivered('c', d(1)), delivered('e', d(2))], now), 3);
      expect(deliveryStreak([delivered('a', d(1)), delivered('b', d(2))], now), 2);
      expect(deliveryStreak([delivered('a', d(2))], now), 0);
      expect(deliveryStreak([Booking.fromMap('x', {'status': 'in_transit', 'timeline': {'delivered': Timestamp.fromDate(d(0))}})], now), 0);
      expect(deliveryStreak(const [], now), 0);
    });

    test('goal share is 0 without a goal and never above 1', () {
      expect(goalShare(500, null), 0);
      expect(goalShare(500, 0), 0);
      expect(goalShare(500, 2000), 0.25);
      expect(goalShare(5000, 2000), 1);
    });

    test('demand: the default knows nothing; the fake answers busiest first and refuses bad points', () async {
      expect(await const NoDemandFeed().near(const GeoPoint2(19, 73)), isEmpty);
      final cells = await const FakeDemandFeed().near(const GeoPoint2(19, 73), max: 2);
      expect(cells.map((c) => c.area), ['Bhiwandi', 'Vashi']);
      expect(await const FakeDemandFeed().near(const GeoPoint2(100, 73)), isEmpty);
    });

    test('daily goal is kept on the phone, cleared, and junk is ignored', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await DailyGoalStore.load(), isNull);
      await DailyGoalStore.save(2500);
      expect(await DailyGoalStore.load(), 2500);
      await DailyGoalStore.save(null);
      expect(await DailyGoalStore.load(), isNull);
      SharedPreferences.setMockInitialValues({DailyGoalStore.key: -4});
      expect(await DailyGoalStore.load(), isNull);
    });
  });

  group('widgets', () {
    tearDown(() => DsMotion.lowEnd = false);

    Widget host(Widget child, {AppLanguage lang = AppLanguage.english, Brightness b = Brightness.light, double scale = 1, bool disableAnimations = false, bool lowEnd = false}) => LanguageScope(
          notifier: ValueNotifier(lang),
          child: MaterialApp(
            theme: AppTheme.build(b, style: ThemeStyle.signature, lowEnd: lowEnd),
            builder: (c, w) => MediaQuery(
              data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: disableAnimations),
              child: Directionality(textDirection: lang.textDirection, child: w!),
            ),
            home: Scaffold(body: ListView(padding: const EdgeInsets.all(16), children: [child])),
          ),
        );

    testWidgets('radar pulse moves only while online and with motion allowed', (t) async {
      double? phase() => (t.widget<CustomPaint>(find.descendant(of: find.byType(RadarPulse), matching: find.byType(CustomPaint))).painter as dynamic).t as double?;
      await t.pumpWidget(host(const RadarPulse(active: true, color: Colors.green)));
      await t.pump(const Duration(milliseconds: 100));
      final a = phase();
      await t.pump(const Duration(milliseconds: 400));
      expect(phase(), isNot(a), reason: 'online: moving');
      await t.pumpWidget(host(const RadarPulse(active: false, color: Colors.green)));
      await t.pump(const Duration(milliseconds: 400));
      expect(phase(), isNull, reason: 'offline: dot only');
      await t.pumpWidget(host(const RadarPulse(active: true, color: Colors.green), disableAnimations: true));
      await t.pump(const Duration(milliseconds: 100));
      final still = phase();
      await t.pump(const Duration(milliseconds: 400));
      expect(phase(), still, reason: 'reduce motion: still');
      expect(still, isNotNull);
      await t.pumpWidget(host(const RadarPulse(key: ValueKey(2), active: true, color: Colors.green), lowEnd: true));
      await t.pump(const Duration(milliseconds: 100));
      final low = phase();
      await t.pump(const Duration(milliseconds: 400));
      expect(phase(), low, reason: 'LowEndMode: still');
    });

    testWidgets('earnings ring says the amount and the goal; a tap asks for a goal and validates it', (t) async {
      final sem = t.ensureSemantics();
      int? asked;
      await t.pumpWidget(host(Builder(
        builder: (context) => EarningsRing(
          todayRupees: 600,
          goalRupees: 2000,
          color: Colors.black,
          track: Colors.grey,
          onSetGoal: () async => asked = await askDailyGoal(context, 2000),
        ),
      )));
      expect(find.text('30%'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('of your')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('d3Ring')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('d3GoalField')), '0');
      await t.tap(find.byKey(const ValueKey('d3GoalSave')));
      await t.pump();
      expect(find.text(T.get('invalidNumber', AppLanguage.english)), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('d3GoalField')), '3000');
      await t.tap(find.byKey(const ValueKey('d3GoalSave')));
      await t.pumpAndSettle();
      expect(asked, 3000);
      sem.dispose();
    });

    testWidgets('papers: expired beats running out; all good otherwise', (t) async {
      await t.pumpWidget(host(Column(children: [
        PaperHealthCard(health: const PaperHealth(expired: 1, expiring: 2, vehicles: 1), onOpen: () {}),
        PaperHealthCard(health: const PaperHealth(expired: 0, expiring: 2, vehicles: 1), onOpen: () {}),
        PaperHealthCard(health: const PaperHealth(expired: 0, expiring: 0, vehicles: 1), onOpen: () {}),
      ])));
      expect(find.text('1 paper(s) expired. Renew to keep taking loads.'), findsOneWidget);
      expect(find.text('2 paper(s) run out within 30 days.'), findsOneWidget);
      expect(find.text('All papers are valid.'), findsOneWidget);
    });

    testWidgets('level card names the level, the next step and the streak; demand strip hides when empty', (t) async {
      await t.pumpWidget(host(Column(children: [
        const LevelStreakCard(delivered: 12, streak: 3),
        const DemandStrip(cells: []),
      ])));
      expect(find.text('Regular'), findsOneWidget);
      expect(find.text('38 more delivered trips to Pro'), findsOneWidget);
      expect(find.byKey(const ValueKey('d3Streak')), findsOneWidget);
      expect(find.byKey(const ValueKey('d3Demand')), findsNothing);
      await t.pumpWidget(host(const DemandStrip(cells: [DemandCell('Vashi', 9)])));
      expect(find.text('Vashi: 9 loads'), findsOneWidget);
    });

    for (final (lang, b) in [(AppLanguage.hindi, Brightness.light), (AppLanguage.urdu, Brightness.dark), (AppLanguage.tamil, Brightness.dark)]) {
      testWidgets('no overflow at 320 dp and 2.0x: ${lang.name} ${b.name}', (t) async {
        t.view.physicalSize = const Size(320, 1600);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(host(
            Column(children: [
              EarningsRing(todayRupees: 12500, goalRupees: 30000, color: Colors.black, track: Colors.grey, onSetGoal: () {}),
              PaperHealthCard(health: const PaperHealth(expired: 2, expiring: 0, vehicles: 1), onOpen: () {}),
              const LevelStreakCard(delivered: 120, streak: 14),
              const DemandStrip(cells: [DemandCell('Bhiwandi', 14), DemandCell('Vashi', 9)]),
            ]),
            lang: lang,
            b: b,
            scale: 2,
            disableAnimations: true));
        await t.pump();
        expect(t.takeException(), isNull);
      });
    }
  });
}
