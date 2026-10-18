import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/offer.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/driver/v2/driver_bid_sheet.dart';

/// U29: the driver's bid sheet: send, change once, withdraw.
void main() {
  late FakeFirebaseFirestore db;
  String? uid;
  late String loadId;
  late Vehicle vehicle;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => uid);
    languageNotifier.value = AppLanguage.english;
    uid = 'customer1';
    loadId = await LoadService.post(pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: 25000, pickupDate: DateTime(2030, 10, 5), notes: '');
    uid = 'driver1';
    await db.collection('users').doc('driver1').set({'driverName': 'Ramesh'});
    final vid = await VehicleService.add(number: 'MH12AB1234', type: '14ft', capacity: 4, rcNumber: 'RC');
    vehicle = Vehicle.fromDoc(await db.collection('vehicles').doc(vid).get());
  });

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 5; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> open(WidgetTester t, {Offer? existing, bool Function()? result}) async {
    t.view.physicalSize = const Size(360 * 2, 900 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final load = Load.fromDoc(await t.runAsync(() => db.collection('loads').doc(loadId).get()) as DocumentSnapshot<Map<String, dynamic>>);
    await t.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(theme: AppTheme.build(Brightness.light), home: Scaffold(body: SingleChildScrollView(child: DriverBidSheet(load: load, vehicle: vehicle, pickupKm: 3, existing: existing)))),
    ));
    await settle(t);
  }

  testWidgets('pick +5%, an ETA and a note, send: one pending offer with those values', (t) async {
    await open(t);
    await t.tap(find.byKey(const ValueKey('bsPct_5')));
    await t.pump();
    expect(find.byKey(const ValueKey('bsPrice')), findsOneWidget);
    await t.tap(find.text('30 min away'));
    await t.pump();
    await t.tap(find.text('I am on the way'));
    await t.pump();
    await t.ensureVisible(find.byKey(const ValueKey('bsSend')));
    await t.tap(find.byKey(const ValueKey('bsSend')));
    await settle(t);
    final offers = await t.runAsync(() => db.collection('offers').get());
    expect(offers!.docs.length, 1);
    final d = offers.docs.single.data();
    expect(d['etaMinutes'], 30);
    expect(d['noteChip'], 'on_the_way');
    expect(d['pickupKm'], 3);
    expect(d['status'], 'pending');
    expect((d['pricePaise'] as int) % 1000, 0, reason: 'rounded to ten rupees');
  });

  testWidgets('a bid already changed once is locked: only Withdraw is left', (t) async {
    await open(t);
    await t.ensureVisible(find.byKey(const ValueKey('bsSend')));
    await t.tap(find.byKey(const ValueKey('bsSend')));
    await settle(t);
    final snap = await t.runAsync(() => db.collection('offers').get());
    await t.runAsync(() => snap!.docs.single.reference.update({'edited': true}));
    final offer = Offer.fromDoc(await t.runAsync(() => db.collection('offers').doc(snap!.docs.single.id).get()) as DocumentSnapshot<Map<String, dynamic>>);
    await open(t, existing: offer);
    expect(find.byKey(const ValueKey('bsLocked')), findsOneWidget);
    expect(find.byKey(const ValueKey('bsSend')), findsNothing);
    expect(find.byKey(const ValueKey('bsWithdraw')), findsOneWidget);
  });

  testWidgets('a typed price is sent as it is, in whole rupees', (t) async {
    await open(t);
    await t.enterText(find.byKey(const ValueKey('bsCustom')), '24500');
    await t.pump();
    expect(t.widget<Text>(find.byKey(const ValueKey('bsPrice'))).data, '₹ 24,500');
    await t.ensureVisible(find.byKey(const ValueKey('bsSend')));
    await t.tap(find.byKey(const ValueKey('bsSend')));
    await settle(t);
    final offers = await t.runAsync(() => db.collection('offers').get());
    expect(offers!.docs.single.data()['pricePaise'], 2450000);
  });

  testWidgets('a load with no price at all starts at nothing, has no percent chips, and does not send until a price is typed', (t) async {
    uid = 'customer1';
    final bare = await t.runAsync(() => LoadService.post(pickup: 'Pune', drop: 'Surat', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: null, pickupDate: DateTime(2030, 10, 5), notes: ''));
    uid = 'driver1';
    loadId = bare!;
    await open(t);
    expect(t.widget<Text>(find.byKey(const ValueKey('bsPrice'))).data, '₹ 0');
    expect(find.byKey(const ValueKey('bsPct_5')), findsNothing);
    await t.ensureVisible(find.byKey(const ValueKey('bsSend')));
    await t.tap(find.byKey(const ValueKey('bsSend')));
    await settle(t);
    expect((await t.runAsync(() => db.collection('offers').get()))!.docs, isEmpty);
    await t.enterText(find.byKey(const ValueKey('bsCustom')), '9000');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('bsSend')));
    await settle(t);
    expect((await t.runAsync(() => db.collection('offers').get()))!.docs.single.data()['pricePaise'], 900000);
  });

  test('the percent steps use whole numbers: the same answers for any fare, no float drift', () {
    for (final fare in [1999900, 2500000, 3333300, 99999000]) {
      final m = BidSheetModel(farePaise: fare, estimatePaise: null);
      for (final p in BidSheetModel.percents) {
        final want = (((fare * (100 + p)) ~/ 100 + 500) ~/ 1000) * 1000;
        expect(m.priceAt(p), want.clamp(m.lowest, m.highest), reason: 'fare $fare at $p%');
      }
    }
  });
}
