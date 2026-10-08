import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/bilty/bilty_card.dart';
import 'package:transport_app/core/bilty/lr_copy_screen.dart';
import 'package:transport_app/core/bilty/lr_model.dart';
import 'package:transport_app/core/bilty/lr_service.dart';
import 'package:transport_app/core/bilty/lr_visibility.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/services/backend.dart';

import '../test_utils.dart';

/// A transporter makes an LR in the form, sends the driver copy, and the
/// assigned driver sees it on the trip screen without any rate.
void main() {
  late FakeFirebaseFirestore db;
  String? uid;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => uid);
    languageNotifier.value = AppLanguage.english;
    await db.collection('users').doc('tr1').set({'role': 'fleet', 'name': 'Ravi', 'companyName': 'Fast Cargo'});
    await db.collection('bookings').doc('B1').set({
      'loadId': 'L1', 'driverId': 'tr1', 'vehicleId': 'v1', 'customerId': 'customer1', 'status': 'accepted', 'pickup': 'Delhi', 'drop': 'Jaipur',
      'cargoType': 'FMCG', 'weight': 7, 'vehicleType': '20ft', 'vehicleNumber': 'MH12AB1234', 'driverName': 'Ravi', 'driverPhone': '', 'timeline': <String, dynamic>{},
      'fleetOwnerId': 'tr1', 'assignedDriverId': 'drvA', 'assignedDriverName': 'Suresh', 'assignedVehicleNumber': 'MH12AB1234', 'createdAt': Timestamp.now(), 'updatedAt': Timestamp.now(),
    });
  });

  testWidgets('transporter creates the LR from the form, the driver gets the driver copy and never a rate', (tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final booking = Booking.fromDoc(await db.collection('bookings').doc('B1').get());
    Widget app(Widget w) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w)));

    // 1. Transporter: no LR yet -> Create -> fill -> saved.
    uid = 'tr1';
    await tester.pumpWidget(app(Builder(builder: (c) => BiltyCard(booking: booking))));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('biltyCreate')));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('lrConsignor')), 'A Traders');
    await tester.enterText(find.byKey(const ValueKey('lrConsignee')), 'B Stores');
    await tester.enterText(find.byKey(const ValueKey('lrFreight')), '25000');
    await tester.enterText(find.byKey(const ValueKey('lrAdvance')), '5000');
    await tester.enterText(find.byKey(const ValueKey('lrMargin')), '1000');
    await tester.enterText(find.byKey(const ValueKey('lrEway')), '123456789012');
    await tester.ensureVisible(find.byKey(const ValueKey('lrSave')));
    await tester.tap(find.byKey(const ValueKey('lrSave')));
    await settle(tester);
    final all = await tester.runAsync(() => LrService.watchForBooking('B1').first);
    expect(all!.single.lrNo, 'TR-${DateTime.now().year}-000001');
    final details = (await db.collection('lrs').doc(all.single.id).collection('private').doc('details').get()).data()!;
    expect(details['freightPaise'], 2500000);
    expect(details['advancePaise'], 500000);
    expect(details['balancePaise'], 2000000);
    expect(details['marginPaise'], 100000);

    // 2. Transporter sends it to the driver.
    final lr = all.single;
    await tester.runAsync(() => LrService.sendToDriver(booking, lr));

    // 3. The driver's trip screen: button, copy, label, no rate anywhere.
    uid = 'drvA';
    await tester.pumpWidget(app(DriverLrButton(key: UniqueKey(), booking: booking)));
    await settle(tester);
    expect(find.byKey(const ValueKey('driverLrCopy')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('driverLrCopy')));
    await settle(tester);
    expect(find.text('Rate hidden by owner'), findsOneWidget);
    expect(find.text('Delhi → Jaipur'), findsOneWidget);
    expect(find.text('B Stores'), findsOneWidget);
    for (final k in ['blFreight', 'blAdvance', 'blBalance', 'blMargin', 'blGst', 'blConsignorPhone', 'blConsigneePhone', 'blEway', 'blGoodsValue']) {
      expect(find.byKey(ValueKey('lrRow_$k')), findsNothing, reason: '$k must not be on the driver copy');
    }
    expect(find.textContaining('25,000'), findsNothing);
    expect(find.textContaining('123456789012'), findsNothing);

    // 4. Whatever the data holds, the driver copy builder leaves the rate out.
    final bundle = await tester.runAsync(() async {
      uid = 'tr1';
      return LrService.bundle(lr);
    });
    final snap = LrVisibility.snapshot(bundle!, LrCopy.driver);
    expect(snap.keys.toSet().intersection({...LrFields.rateKeys, 'marginPaise', ...LrFields.phoneKeys, ...LrFields.complianceKeys}), isEmpty);
    expect(find.byType(LrCopyCard), findsOneWidget);
  });
}
