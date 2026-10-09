import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/bilty/bilty_card.dart';
import 'package:transport_app/core/bilty/inspection_service.dart';
import 'package:transport_app/core/bilty/inspection_widgets.dart';
import 'package:transport_app/core/bilty/lr_model.dart';
import 'package:transport_app/core/bilty/lr_service.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/services/backend.dart';

import 'test_utils.dart';

/// MASTER-6 Task 32: inspection mode shows the trip to the owner and keeps a history.
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

  Future<(Booking, LrPublic)> issued() async {
    final booking = Booking.fromDoc(await db.collection('bookings').doc('B1').get());
    uid = 'tr1';
    final lr = await LrService.issue(booking, const LrDraft(consignorName: 'A', consigneeName: 'B', goods: 'FMCG', freightPaise: 2500000, goodsValuePaise: 90000000, invoiceNo: 'INV-1', complianceMode: 'inspection_on_request'));
    return (booking, lr);
  }

  test('every step of inspection mode leaves one line: asked, approved, refused, allowed in advance, ended', () async {
    final (b, lr) = await issued();
    uid = 'drvA';
    await InspectionService.request(b, lr, driverName: 'Suresh');
    uid = 'tr1';
    await InspectionService.respond(b, lr, 'drvA', approve: false);
    uid = 'drvA';
    await InspectionService.request(b, lr, driverName: 'Suresh');
    uid = 'tr1';
    clock = clock.add(const Duration(minutes: 1));
    await InspectionService.respond(b, lr, 'drvA', approve: true);
    clock = clock.add(const Duration(minutes: 1));
    await InspectionService.allowFor(b, lr, 24);
    await InspectionService.revoke(lr, 'drvA');
    final kinds = (await db.collection('lrs').doc(lr.id).collection('inspection_log').get()).docs.map((d) => d.data()['kind']).toList()..sort();
    expect(kinds, ['allowed', 'approved', 'denied', 'requested', 'requested', 'revoked']);
    final byKind = {for (final d in (await db.collection('lrs').doc(lr.id).collection('inspection_log').get()).docs) d.data()['kind']: d.data()};
    expect(byKind['approved']!['hours'], 2);
    expect(byKind['allowed']!['hours'], 24);
    expect(byKind['requested']!['by'], 'drvA');
    expect(byKind['denied']!['by'], 'tr1');
    expect(byKind['revoked']!.containsKey('hours'), isFalse);
  });

  testWidgets('the request shows the owner the trip and what the driver would see; the history lists what happened', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late Booking booking;
    late LrPublic lr;
    await tester.runAsync(() async {
      (booking, lr) = await issued();
      uid = 'drvA';
      await InspectionService.request(booking, lr, driverName: 'Suresh');
    });
    uid = 'tr1';
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: BiltyCard(key: UniqueKey(), booking: booking))))));
    await settle(tester);
    expect(find.byKey(const ValueKey('inCtx_drvA')), findsOneWidget);
    final ctx = tester.widget<Text>(find.byKey(const ValueKey('inCtx_drvA'))).data!;
    expect(ctx, contains(lr.lrNo));
    expect(ctx, contains('Delhi'));
    expect(ctx, contains('Jaipur'));
    expect(ctx, contains('MH12AB1234'));
    expect(find.byKey(const ValueKey('inSees_drvA')), findsOneWidget);
    expect(find.textContaining('never the rate or phone numbers'), findsOneWidget);
    expect(find.byKey(const ValueKey('inHistory')), findsOneWidget);
    expect(find.text('The driver asked to show the LR'), findsNothing); // the line carries a time before it
    expect(find.textContaining('The driver asked to show the LR'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('inApprove_drvA')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await settle(tester);
    expect(find.textContaining('Approved for 2 hours'), findsOneWidget);
  });

  testWidgets('the history widget is hidden when nothing has happened', (tester) async {
    final (_, lr) = await tester.runAsync(issued) as (Booking, LrPublic);
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: InspectionHistory(lr: lr)))));
    await settle(tester);
    expect(find.byKey(const ValueKey('inHistory')), findsNothing);
  });
}
