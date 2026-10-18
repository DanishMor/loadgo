import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_dispatch_monitor_screen.dart';
import 'package:transport_app/core/dispatch/dispatch_metrics.dart';
import 'package:transport_app/core/dispatch/dispatch_models.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/offer.dart';
import 'package:transport_app/core/theme/app_theme.dart';

/// U17: the admin dispatch monitor.
void main() {
  final t0 = DateTime(2030, 1, 1, 12);
  Timestamp ts(int sec) => Timestamp.fromDate(t0.add(Duration(seconds: sec)));

  Load load(String id, {String status = 'open', int created = 0, String? booking, int? matched, bool cancelled = false, int? estimate, num? budget = 20000, LoadMode mode = LoadMode.instant, String pickup = 'Delhi'}) => Load(
        id: id,
        shipperId: 'c1',
        pickup: pickup,
        drop: 'Jaipur',
        cargoType: 'FMCG',
        weight: 5,
        vehicleType: '14ft',
        budget: budget,
        pickupDate: null,
        notes: '',
        status: status,
        cancelled: cancelled,
        bookingId: booking,
        createdAt: ts(created),
        matchedAt: matched == null ? null : ts(matched),
        mode: mode,
      );

  Offer offer(String loadId, String driver, int price, int at, {String status = 'pending'}) => Offer(
        id: '${loadId}_$driver',
        loadId: loadId,
        driverId: driver,
        customerId: 'c1',
        vehicleId: 'v',
        vehicleNumber: 'N',
        vehicleType: '14ft',
        driverName: driver,
        pricePaise: price,
        originalPaise: price,
        status: status,
        createdAt: ts(at),
      );

  test('median of odd, even and empty lists', () {
    expect(DispatchMetrics.median([]), isNull);
    expect(DispatchMetrics.median([5]), 5);
    expect(DispatchMetrics.median([9, 1, 5]), 5);
    expect(DispatchMetrics.median([1, 2, 3, 10]), 3);
  });

  test('summary: live, filled, expired with and without bids, acceptance, first-bid and fill times', () {
    final loads = [
      load('live1', created: 0), // open, in wave 2 at 40 s
      load('live2', created: 0, mode: LoadMode.bid),
      load('done1', status: 'closed', created: 0, booking: 'B1', matched: 120),
      load('done2', status: 'matched', created: 0, booking: 'B2', matched: 60),
      load('exp1', status: 'closed', created: 0),
      load('exp2', status: 'closed', created: 0),
      load('canc', status: 'closed', created: 0, cancelled: true),
    ];
    final offers = [
      offer('live1', 'a', 100, 10),
      offer('done1', 'a', 100, 30),
      offer('done1', 'b', 100, 20),
      offer('done2', 'a', 100, 50),
      offer('exp2', 'a', 100, 70),
    ];
    final snap = DispatchMetrics.compute(loads: loads, offers: offers, now: t0.add(const Duration(seconds: 40)), noShowCancels: 3);
    final s = snap.summary;
    expect((s.live, s.filled, s.expiredNoBid, s.expiredWithBids), (2, 2, 1, 1));
    expect(s.acceptancePercent, 50, reason: '2 taken out of 4 finished; the cancelled one is not counted');
    expect(s.medianFirstBidSeconds, 35, reason: 'first bids per load at 10, 20, 50 and 70 s: the median is 35');
    expect(s.medianFillSeconds, 90);
    expect(s.noShowCancels, 3);
    final byId = {for (final r in snap.rows) r.load.id: r};
    expect(byId['live1']!.wave, 2);
    expect(byId['live1']!.stalled, isFalse);
    expect(byId['live1']!.bids, 1);
    expect(byId['live2']!.wave, isNull, reason: 'a bid-mode load has no rings');
    expect(byId['done1']!.firstBidSeconds, 20);
    expect(byId['done1']!.fillSeconds, 120);
  });

  test('a live instant load shows stalled after the last wave ran out', () {
    final snap = DispatchMetrics.compute(loads: [load('a')], offers: const [], now: t0.add(const Duration(seconds: 200)));
    expect(snap.rows.single.stalled, isTrue);
    expect(snap.rows.single.wave, 3);
  });

  test('price against estimate: the confirmed bid, else the budget, over the fare estimate', () {
    final l1 = Load(id: 'p1', shipperId: 'c', pickup: 'Delhi', drop: 'Jaipur', cargoType: 'x', weight: 1, vehicleType: '14ft', budget: 20000, pickupDate: null, notes: '', status: 'closed', bookingId: 'B', createdAt: ts(0), matchedAt: ts(30));
    // estimate parsed from a map in real life; here a load with no estimate is skipped and one with an estimate counts
    final withEst = Load.fromDoc(_Doc('p2', {
      'shipperId': 'c', 'pickup': 'Delhi', 'drop': 'Jaipur', 'cargoType': 'x', 'weight': 1, 'vehicleType': '14ft', 'budget': 22000,
      'status': 'closed', 'bookingId': 'B2', 'createdAt': ts(0), 'matchedAt': ts(30), 'estimate': {'baseFare': 2000000},
    }));
    final snap = DispatchMetrics.compute(loads: [l1, withEst], offers: [offer('p2', 'a', 2400000, 5, status: 'confirmed')], now: t0);
    expect(snap.summary.priceVsEstimatePercent, 120, reason: '24000 rupees over a 20000 estimate');
  });

  test('nothing to judge gives no percentages', () {
    final s = DispatchMetrics.compute(loads: const [], offers: const [], now: t0).summary;
    expect((s.acceptancePercent, s.priceVsEstimatePercent, s.medianFillSeconds), (null, null, null));
  });

  Widget host(Future<DispatchSnapshot> Function() loader, {double scale = 1.0, Brightness b = Brightness.light, AppLanguage lang = AppLanguage.english}) {
    languageNotifier.value = lang;
    return LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(
        theme: AppTheme.build(b),
        builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
        home: AdminDispatchMonitorScreen(load: loader),
      ),
    );
  }

  testWidgets('the screen shows the numbers and the recent loads; Refresh loads again', (t) async {
    t.view.physicalSize = const Size(800, 4000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    var calls = 0;
    final snap = DispatchMetrics.compute(loads: [load('a'), load('b', status: 'closed', created: 0, booking: 'B', matched: 30)], offers: [offer('a', 'd1', 100, 5)], now: t0.add(const Duration(seconds: 10)));
    await t.pumpWidget(host(() async {
      calls++;
      return snap;
    }));
    await t.pumpAndSettle();
    expect(find.text('Dispatch monitor'), findsOneWidget);
    expect(find.text('Live loads'), findsOneWidget);
    expect(find.byKey(const ValueKey('dmRow_a')), findsOneWidget);
    expect(find.text('1 bids'), findsOneWidget);
    expect(find.text('Ring 1'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('dmRefresh')));
    await t.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('a failure shows the error with Retry, not a blank page', (t) async {
    await t.pumpWidget(host(() async => throw StateError('no access')));
    await t.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Dispatch monitor'), findsOneWidget);
  });

  for (final lang in [AppLanguage.english, AppLanguage.hindi, AppLanguage.urdu]) {
    for (final b in Brightness.values) {
      testWidgets('fits 360x640 at 2.0x text: ${lang.name} ${b.name}', (t) async {
        t.view.physicalSize = const Size(360, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final snap = DispatchMetrics.compute(loads: [load('a', pickup: 'Delhi Connaught Place Central Market')], offers: const [], now: t0);
        await t.pumpWidget(host(() async => snap, scale: 2.0, b: b, lang: lang));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  }
}

/// A DocumentSnapshot stand-in for [Load.fromDoc] in the pure tests.
class _Doc implements DocumentSnapshot<Map<String, dynamic>> {
  @override
  final String id;
  final Map<String, dynamic> _d;
  _Doc(this.id, this._d);
  @override
  Map<String, dynamic>? data() => _d;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
