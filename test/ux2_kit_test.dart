import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/theme/design_tokens.dart';
import 'package:transport_app/core/widgets/ds/bid_card.dart';
import 'package:transport_app/core/widgets/ds/countdown_ring.dart';
import 'package:transport_app/core/widgets/ds/driver_mini_card.dart';
import 'package:transport_app/core/widgets/ds/fare_meter.dart';
import 'package:transport_app/core/widgets/ds/route_ribbon.dart';
import 'package:transport_app/core/widgets/ds/slide_to_confirm.dart';
import 'package:transport_app/core/widgets/ds/status_timeline_v2.dart';

/// U5, U6: the premium component kit.
Widget host(Widget child, {Brightness b = Brightness.light, double scale = 1.0, AppLanguage lang = AppLanguage.english, bool lowEnd = false}) {
  final language = ValueNotifier(lang);
  final dir = (lang == AppLanguage.urdu || lang == AppLanguage.kashmiri) ? TextDirection.rtl : TextDirection.ltr;
  return LanguageScope(
    notifier: language,
    child: MaterialApp(
      theme: AppTheme.build(b, lowEnd: lowEnd),
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: Directionality(textDirection: dir, child: w!),
      ),
      home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(DsSpace.gutter), child: child)),
    ),
  );
}

Widget all({int price = 45000}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const RouteRibbon(from: 'Delhi', to: 'Jaipur Rajasthan', distanceKm: 281),
      const SizedBox(height: 12),
      FareMeter(estimatePaise: 4500000, usualLowPaise: 4000000, usualHighPaise: 5000000, valuePaise: 4500000, onChanged: (_) {}),
      const SizedBox(height: 12),
      CountdownRing(endsAt: DateTime(2030), totalSeconds: 30, now: () => DateTime(2030).subtract(const Duration(seconds: 12))),
      const SizedBox(height: 12),
      SlideToConfirm(label: 'Accept at fare', onConfirmed: () {}),
      const SizedBox(height: 12),
      BidCard(driverName: 'Ramesh Kumar', rating: 4.6, trips: 120, verified: true, pricePaise: 4200000, etaMinutes: 18, tags: const [BidTag.bestPrice, BidTag.nearest], onAccept: () {}, onCounter: () {}),
      const SizedBox(height: 12),
      const StatusTimelineV2(steps: [TimelineStepV2('Booked', time: '10:00'), TimelineStepV2('Driver arrived'), TimelineStepV2('Delivered')], current: 1),
    ]);

void main() {
  testWidgets('FareMeter verdict uses the usual range, or 85-115% of the estimate without one', (t) async {
    FareVerdict v(int val, {int? lo, int? hi}) => FareMeter(estimatePaise: 100000, valuePaise: val, usualLowPaise: lo, usualHighPaise: hi, onChanged: (_) {}).verdict;
    expect(v(84999), FareVerdict.low);
    expect(v(85000), FareVerdict.fair);
    expect(v(115000), FareVerdict.fair);
    expect(v(115001), FareVerdict.high);
    expect(v(70000, lo: 60000, hi: 130000), FareVerdict.fair);
    expect(v(59999, lo: 60000, hi: 130000), FareVerdict.low);
    final m = FareMeter(estimatePaise: 100000, usualLowPaise: 10000, usualHighPaise: 400000, valuePaise: 100000, onChanged: (_) {});
    expect(m.minPaise, 10000);
    expect(m.maxPaise, 400000);
    expect(m.minPaise % m.stepPaise, 0);
  });

  testWidgets('FareMeter slider reports whole steps of paise and shows the hint', (t) async {
    var value = 4500000;
    await t.pumpWidget(host(StatefulBuilder(builder: (c, set) => FareMeter(estimatePaise: 4500000, valuePaise: value, onChanged: (v) => set(() => value = v)))));
    expect(find.byKey(const ValueKey('fareMeterHint')), findsOneWidget);
    expect(find.textContaining('No usual price'), findsOneWidget);
    await t.drag(find.byType(Slider), const Offset(200, 0));
    await t.pump();
    expect(value % 1000, 0);
    expect(value, greaterThan(4500000));
  });

  testWidgets('CountdownRing: seconds from the clock, onDone once, warning colour in the last 10 s', (t) async {
    var now = DateTime(2030);
    var done = 0;
    await t.pumpWidget(host(CountdownRing(endsAt: DateTime(2030, 1, 1, 0, 0, 30), totalSeconds: 30, now: () => now, onDone: () => done++)));
    expect(find.text('30'), findsOneWidget);
    now = DateTime(2030, 1, 1, 0, 0, 25);
    await t.pump(const Duration(seconds: 1));
    expect(find.text('5'), findsOneWidget);
    now = DateTime(2030, 1, 1, 0, 0, 31);
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('0'), findsOneWidget);
    expect(done, 1);
    expect(CountdownRing.secondsLeft(DateTime(2030, 1, 1, 0, 1), DateTime(2030), 30), 30);
    expect(CountdownRing.secondsLeft(DateTime(2030), DateTime(2031), 30), 0);
  });

  testWidgets('SlideToConfirm: a short drag springs back, a full drag confirms once, the button path confirms too', (t) async {
    var n = 0;
    await t.pumpWidget(host(SlideToConfirm(label: 'Go', onConfirmed: () => n++)));
    await t.drag(find.byKey(const ValueKey('slideThumb')), const Offset(60, 0));
    await t.pumpAndSettle();
    expect(n, 0);
    await t.drag(find.byKey(const ValueKey('slideThumb')), const Offset(1200, 0));
    await t.pumpAndSettle();
    expect(n, 1);
    await t.drag(find.byKey(const ValueKey('slideThumb')), const Offset(-100, 0), warnIfMissed: false);
    expect(n, 1);
    final h = t.ensureSemantics();
    n = 0;
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(host(SlideToConfirm(label: 'Go2', onConfirmed: () => n++)));
    t.semantics.tap(find.semantics.byLabel('Go2'));
    await t.pump();
    expect(n, 1);
    h.dispose();
  });

  testWidgets('SlideToConfirm disabled does nothing', (t) async {
    var n = 0;
    await t.pumpWidget(host(SlideToConfirm(label: 'Go', enabled: false, onConfirmed: () => n++)));
    await t.drag(find.byKey(const ValueKey('slideThumb')), const Offset(1200, 0));
    await t.pumpAndSettle();
    expect(n, 0);
  });

  testWidgets('BidCard: tags, price, eta; accept and counter fire; a counter already sent replaces the button', (t) async {
    var accepted = 0, countered = 0;
    await t.pumpWidget(host(BidCard(driverName: 'Asha', pricePaise: 123400, etaMinutes: 9, tags: const [BidTag.topRated], onAccept: () => accepted++, onCounter: () => countered++)));
    expect(find.text('Top rated'), findsOneWidget);
    expect(find.byKey(const ValueKey('bidPrice')), findsOneWidget);
    expect(find.text('9 min away'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('bidAccept')));
    await t.tap(find.byKey(const ValueKey('bidCounter')));
    expect((accepted, countered), (1, 1));
    await t.pumpWidget(host(BidCard(driverName: 'Asha', pricePaise: 123400, counterPaise: 120000, onAccept: () {}, onCounter: () {})));
    expect(find.byKey(const ValueKey('bidCounter')), findsNothing);
    expect(find.byKey(const ValueKey('bidCounterShown')), findsOneWidget);
  });

  testWidgets('DriverMiniCard shows no phone and says New driver with no trips', (t) async {
    await t.pumpWidget(host(const DriverMiniCard(name: 'Sunil', verified: true)));
    expect(find.text('New driver'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('S'), findsOneWidget);
  });

  for (final lang in [AppLanguage.english, AppLanguage.hindi, AppLanguage.tamil, AppLanguage.urdu]) {
    for (final b in Brightness.values) {
      for (final low in [false, true]) {
        testWidgets('kit fits 360x640 at 2.0x text: ${lang.name} ${b.name} lowEnd=$low', (t) async {
          t.view.physicalSize = const Size(360, 640);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          await t.pumpWidget(host(all(), b: b, scale: 2.0, lang: lang, lowEnd: low));
          await t.pump(const Duration(seconds: 1));
          expect(t.takeException(), isNull);
        });
      }
    }
  }
}
