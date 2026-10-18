import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/pricing/fare_calculator.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/transporter/transporter_logic.dart';
import 'package:transport_app/fleet/transporter_loads_screen.dart';

import 'test_utils.dart';

/// U35: the transporter's loads tab bids for the company through the same bid sheet as the driver.
void main() {
  FareBreakdown fare(int total) => FareBreakdown(distanceKm: 100, baseFare: total, distanceCharge: 0, loadingCharge: 0, unloadingCharge: 0, waitingCharge: 0, extraStopCharge: 0, minimumFareAdjustment: 0, platformFee: 0, gst: 0, platformFeePercent: 0, gstPercent: 0);

  final load = Load(
    id: 'a', shipperId: 'c1', pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 8, vehicleType: '20ft', budget: null, pickupDate: null, notes: '', status: 'open', estimate: fare(400000),
  );
  final vehicle = Vehicle(id: 'v1', ownerId: 'tr1', number: 'MH12ABv1', type: '20ft', capacity: 10, rcNumber: 'R', status: 'active');

  late FakeFirebaseFirestore db;
  setUp(() async {
    FeaturesService.reset();
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'tr1');
    languageNotifier.value = AppLanguage.english;
    await db.collection('users').doc('tr1').set({'companyName': 'Acme Roadways', 'verified': true, 'role': 'fleet'});
    await db.collection('loads').doc('a').set({'shipperId': 'c1', 'pickup': 'Delhi', 'drop': 'Jaipur', 'cargoType': 'FMCG', 'weight': 8, 'vehicleType': '20ft', 'status': 'open', 'estimate': {'total': 400000, 'distanceKm': 100}});
  });
  tearDown(FeaturesService.reset);

  Future<void> show(WidgetTester t, {Brightness b = Brightness.light, double scale = 1}) async {
    t.view.physicalSize = const Size(360 * 2, 900 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(
        theme: AppTheme.build(b),
        builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
        home: Scaffold(body: TransporterLoadsScreen(loads: Stream.value([load]), vehicles: () async => [vehicle], profile: () async => const TransporterProfile())),
      ),
    ));
    await settle(t);
  }

  testWidgets('Bid opens the vehicle choice, then the bid sheet; sending stores a company offer', (t) async {
    await show(t);
    await t.tap(find.byKey(const ValueKey('trpBidButton_a')));
    await settle(t);
    await t.tap(find.byKey(const ValueKey('bidVehicle_v1')));
    await settle(t);
    expect(find.byKey(const ValueKey('bsSend')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('bsPct_5')));
    await t.pump();
    await t.ensureVisible(find.byKey(const ValueKey('bsSend')));
    await t.tap(find.byKey(const ValueKey('bsSend')));
    await settle(t);
    final offers = await t.runAsync(() => db.collection('offers').get());
    expect(offers!.docs.length, 1);
    final d = offers.docs.single.data();
    expect(d['fleetOwnerId'], 'tr1');
    expect(d['driverName'], 'Acme Roadways');
    expect(d['status'], 'pending');
    expect(d['pricePaise'], 420000);
  });

  testWidgets('dark and 2.0x text: no overflow', (t) async {
    await show(t, b: Brightness.dark, scale: 2);
    expect(t.takeException(), isNull);
  });

  testWidgets('uiV2 off: the old price dialog, not the bid sheet', (t) async {
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.uiV2: false});
    await show(t);
    await t.tap(find.byKey(const ValueKey('trpBidButton_a')));
    await settle(t);
    await t.tap(find.byKey(const ValueKey('bidVehicle_v1')));
    await settle(t);
    expect(find.byKey(const ValueKey('bsSend')), findsNothing);
    expect(find.byKey(const ValueKey('priceField')), findsOneWidget);
  });
}
