
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/pricing/fare_calculator.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/pricing/offer_bounds.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/transporter/bulk_bid.dart';
import 'package:transport_app/core/transporter/transporter_logic.dart';
import 'package:transport_app/fleet/transporter_loads_screen.dart';

import 'test_utils.dart';

/// MASTER-6 Task 29: transporter load filters, saved searches and bulk bid under a margin rule.
void main() {
  final now = DateTime(2026, 10, 9, 12);

  FareBreakdown fare(int total) => FareBreakdown(distanceKm: 100, baseFare: total, distanceCharge: 0, loadingCharge: 0, unloadingCharge: 0, waitingCharge: 0, extraStopCharge: 0, minimumFareAdjustment: 0, platformFee: 0, gst: 0, platformFeePercent: 0, gstPercent: 0);

  Load load(String id, {int? total = 400000, String pickup = 'Delhi', String drop = 'Jaipur', String type = '20ft', num weight = 8}) => Load(
        id: id, shipperId: 'c1', pickup: pickup, drop: drop, cargoType: 'FMCG', weight: weight, vehicleType: type, budget: null, pickupDate: null, notes: '', status: 'open',
        estimate: total == null ? null : fare(total),
      );

  Vehicle veh(String id, {String type = '20ft', num cap = 10, String availability = 'available'}) =>
      Vehicle(id: id, ownerId: 'tr1', number: 'MH12AB$id', type: type, capacity: cap, rcNumber: 'R', status: 'active', availability: availability);

  test('price: estimate plus markup in whole ten rupees, inside the bounds, none without an estimate', () {
    expect(BulkBid.priceFor(400000, 0), 400000);
    expect(BulkBid.priceFor(400000, 10), 440000);
    expect(BulkBid.priceFor(123456, 5), 130000); // 129629 rounds to 130000
    expect(BulkBid.priceFor(null, 5), isNull);
    expect(BulkBid.priceFor(0, 5), isNull);
    for (final e in [1, 7, 500, 99999]) {
      for (final m in BulkBid.markupChoices) {
        expect(OfferBounds.check(BulkBid.priceFor(e, m)!, e), isNull, reason: 'estimate $e markup $m');
      }
    }
  });

  test('vehicle: free, big enough, valid papers; the same type first, then the smallest', () {
    final l = load('a', type: '20ft', weight: 8);
    expect(BulkBid.vehicleFor(l, [veh('v1', cap: 20), veh('v2', cap: 10)], now)!.id, 'v2');
    expect(BulkBid.vehicleFor(l, [veh('v1', type: '14ft', cap: 9), veh('v2', cap: 15)], now)!.id, 'v2'); // the same type wins over a smaller other type
    expect(BulkBid.vehicleFor(l, [veh('v1', cap: 5)], now), isNull);
    expect(BulkBid.vehicleFor(l, [veh('v1', availability: 'on_trip')], now), isNull);
    final expired = Vehicle(id: 'e', ownerId: 'tr1', number: 'X', type: '20ft', capacity: 10, rcNumber: 'R', status: 'active', availability: 'available', docs: {VehicleDocKind.insurance: VehicleDocInfo(number: 'I', expiry: DateTime(2026, 9, 1))});
    expect(BulkBid.vehicleFor(l, [expired], now), isNull);
  });

  test('plan: skips a load with no estimate, no vehicle or too little margin; keeps the rest', () {
    final loads = [load('ok'), load('noEst', total: null), load('heavy', weight: 50), load('thin')];
    final items = BulkBid.plan(
      loads,
      [veh('v1')],
      markupPercent: 0,
      minMarginPercent: 20,
      runningCost: (l, v) => l.id == 'thin' ? 380000 : 100000,
      now: now,
    );
    expect({for (final i in items) i.load.id: i.skip}, {'ok': null, 'noEst': BulkSkip.noEstimate, 'heavy': BulkSkip.noVehicle, 'thin': BulkSkip.lowMargin});
    expect(items.first.marginPaise, 300000);
    expect(items.first.willBid, isTrue);
    // an unknown distance cannot fail the margin rule
    final unknown = BulkBid.plan([load('u')], [veh('v1')], markupPercent: 0, minMarginPercent: 50, runningCost: (l, v) => null, now: now);
    expect(unknown.single.willBid, isTrue);
    expect(unknown.single.marginPaise, isNull);
    // a higher markup can rescue a thin load
    final rescued = BulkBid.plan([load('thin')], [veh('v1')], markupPercent: 20, minMarginPercent: 20, runningCost: (l, v) => 380000, now: now);
    expect(rescued.single.willBid, isTrue);
    // at most maxLoads are planned
    expect(BulkBid.plan([for (var i = 0; i < 30; i++) load('l$i')], [veh('v1')], markupPercent: 0, minMarginPercent: 0, runningCost: (l, v) => 0, now: now).length, BulkBid.maxLoads);
  });

  Widget screen(List<Load> loads) => LanguageScope(
        notifier: languageNotifier,
        child: MaterialApp(home: Scaffold(body: TransporterLoadsScreen(loads: Stream.value(loads), vehicles: () async => [veh('v1')], profile: () async => const TransporterProfile()))),
      );

  testWidgets('filters narrow the list; the filter count shows on the button', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'tr1');
    await tester.pumpWidget(screen([load('a', drop: 'Jaipur'), load('b', drop: 'Mumbai')]));
    await settle(tester);
    expect(find.byKey(const ValueKey('trpLoad_a')), findsOneWidget);
    expect(find.byKey(const ValueKey('trpLoad_b')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('trpFilters')));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('dropFilter')), 'mumbai');
    await tester.ensureVisible(find.byKey(const ValueKey('applyFilters')));
    await tester.tap(find.byKey(const ValueKey('applyFilters')));
    await settle(tester);
    expect(find.byKey(const ValueKey('trpLoad_a')), findsNothing);
    expect(find.byKey(const ValueKey('trpLoad_b')), findsOneWidget);
  });

  testWidgets('select loads, choose markup and margin, see what will be bid, send; the offers are for the company', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'tr1');
    await db.collection('users').doc('tr1').set({'companyName': 'Acme Roadways', 'verified': true, 'role': 'fleet'});
    await tester.pumpWidget(screen([load('a'), load('b', total: null), load('c')]));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('bbSelect')));
    await settle(tester);
    for (final id in ['a', 'b', 'c']) {
      await tester.tap(find.byKey(ValueKey('bbPick_$id')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey('bbBidOn')));
    await settle(tester);
    expect(find.text('Will bid: 2'), findsOneWidget);
    expect(find.text('Left out: 1'), findsOneWidget);
    expect(find.textContaining('no fare estimate to bid from'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bbMarkup_10')));
    await tester.pump();
    expect(find.textContaining('₹ 4,400'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('bbSend')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await settle(tester);
    final offers = (await db.collection('offers').get()).docs;
    expect(offers.map((d) => d.id).toSet(), {'a_tr1', 'c_tr1'});
    expect(offers.first.data()['pricePaise'], 440000);
    expect(offers.first.data()['fleetOwnerId'], 'tr1');
    expect(find.textContaining('Bids sent: 2'), findsOneWidget);
  });

  testWidgets('a load already bid on counts as already bid, not as a failure', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'tr1');
    await db.collection('users').doc('tr1').set({'companyName': 'Acme', 'role': 'fleet'});
    await db.collection('offers').doc('a_tr1').set({'loadId': 'a', 'driverId': 'tr1', 'status': 'pending'});
    await tester.pumpWidget(screen([load('a'), load('c')]));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('bbSelect')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('bbPick_a')));
    await tester.tap(find.byKey(const ValueKey('bbPick_c')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('bbBidOn')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('bbSend')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await settle(tester);
    expect(find.textContaining('Bids sent: 1. Already bid: 1. Not sent: 0.'), findsOneWidget);
  });
}
