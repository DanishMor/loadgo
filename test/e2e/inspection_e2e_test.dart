import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/bilty/bilty_card.dart';
import 'package:transport_app/core/bilty/inspection_service.dart';
import 'package:transport_app/core/bilty/lr_copy_screen.dart';
import 'package:transport_app/core/bilty/lr_service.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/services/backend.dart';

import '../test_utils.dart';

/// The roadside story: the driver is stopped, asks the owner, the owner
/// approves in the app, the driver keeps the inspection copy on the phone, and
/// two hours later the access, the copy and the screen go back to "hidden".
void main() {
  late FakeFirebaseFirestore db;
  String? uid;
  late DateTime clock;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => uid);
    languageNotifier.value = AppLanguage.english;
    clock = DateTime(2026, 10, 8, 10);
    InspectionService.now = () => clock;
    await db.collection('users').doc('tr1').set({'role': 'fleet', 'name': 'Ravi', 'companyName': 'Fast Cargo'});
    await db.collection('users').doc('drvA').set({'role': 'driver', 'driverName': 'Suresh'});
    await db.collection('bookings').doc('B1').set({
      'loadId': 'L1', 'driverId': 'tr1', 'vehicleId': 'v1', 'customerId': 'customer1', 'status': 'in_transit', 'pickup': 'Delhi', 'drop': 'Jaipur', 'cargoType': 'FMCG', 'weight': 7,
      'vehicleType': '20ft', 'vehicleNumber': 'MH12AB1234', 'driverName': 'Ravi', 'driverPhone': '', 'timeline': <String, dynamic>{}, 'fleetOwnerId': 'tr1', 'assignedDriverId': 'drvA',
      'assignedDriverName': 'Suresh', 'createdAt': Timestamp.now(), 'updatedAt': Timestamp.now(),
    });
  });
  tearDown(() => InspectionService.now = DateTime.now);

  testWidgets('request, approve, offline copy, expiry', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final booking = Booking.fromDoc(await db.collection('bookings').doc('B1').get());
    late String lrId;
    await tester.runAsync(() async {
      uid = 'tr1';
      final lr = await LrService.issue(
          booking,
          const LrDraft(consignorName: 'A', consigneeName: 'B', goods: 'FMCG', freightPaise: 2500000, goodsValuePaise: 90000000, invoiceNo: 'INV-1', consignorGstin: '27ABCDE1234F1Z5', ewayBillNo: '123456789012', complianceMode: 'inspection_on_request'));
      lrId = lr.id;
    });

    // 1. The driver is stopped: compliance is hidden, labels are plain, he asks.
    uid = 'drvA';
    await tester.pumpWidget(MaterialApp(home: DriverLrScreen(booking: booking)));
    await settle(tester);
    expect(find.text('Rate hidden by owner'), findsOneWidget);
    expect(find.text('Owner approval needed for inspection'), findsOneWidget);
    expect(find.textContaining('123456789012'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('inRequest')));
    await settle(tester);
    expect(find.byKey(const ValueKey('inPendingLabel')), findsOneWidget);

    // 2. The owner sees the request on the LR card and approves.
    uid = 'tr1';
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: BiltyCard(key: UniqueKey(), booking: booking)))));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('inApprove_drvA')));
    await settle(tester);

    // 3. The driver's phone shows the details and the time; he saves the copy.
    uid = 'drvA';
    await tester.pumpWidget(MaterialApp(home: DriverLrScreen(key: UniqueKey(), booking: booking)));
    await settle(tester);
    expect(find.textContaining('123456789012'), findsOneWidget);
    expect(find.byKey(const ValueKey('inAllowedLabel')), findsOneWidget);
    expect(find.text('Rate hidden by owner'), findsOneWidget);
    expect(find.textContaining('25,00,000'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('inSave')));
    await settle(tester);
    expect(await tester.runAsync(() => InspectionCache().get(lrId, clock)), isNotNull);
    await tester.pumpWidget(MaterialApp(home: DriverLrScreen(key: UniqueKey(), booking: booking)));
    await settle(tester);
    expect(find.byKey(const ValueKey('inShowCopy')), findsOneWidget);

    // 4. Two hours pass: access closes, the copy is deleted, the end is logged.
    clock = clock.add(const Duration(hours: 2, minutes: 1));
    await tester.pump(const Duration(seconds: 16));
    await settle(tester);
    expect(find.textContaining('123456789012'), findsNothing);
    expect(find.byKey(const ValueKey('inNeedApprovalLabel')), findsOneWidget);
    expect(find.byKey(const ValueKey('inShowCopy')), findsNothing);
    expect(await tester.runAsync(() => InspectionCache().get(lrId, clock)), isNull);
    final types = (await tester.runAsync(() => db.collection('audit_events').get()))!.docs.map((d) => d.data()['type']).toList();
    for (final t in ['lr_issue', 'inspection_request', 'inspection_approve', 'inspection_expire']) {
      expect(types, contains(t));
    }
    expect(types.where((t) => t == 'inspection_expire').length, 1);
  });
}
