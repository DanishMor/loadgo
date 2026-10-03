import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/services/admin_service.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/features/admin/admin_verification_screen.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;

  setUp(() async {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'admin1');
    await db.collection('users').doc('d1').set({
      'driverName': 'Ramesh', 'phone': '+911', 'vehicleNumber': 'MH12AB1234', 'vehicleType': '20ft',
      'verified': false, 'verificationStatus': 'pending',
    });
    await db.collection('users').doc('d2').set({
      'driverName': 'Suresh', 'verified': true, 'verificationStatus': 'approved',
    });
  });

  test('setStatus keeps verified in sync with the status', () async {
    await AdminService.setStatus('d1', AdminService.approved);
    var d = (await db.collection('users').doc('d1').get()).data()!;
    expect((d['verified'], d['verificationStatus']), (true, 'approved'));
    await AdminService.setStatus('d1', AdminService.rejected);
    d = (await db.collection('users').doc('d1').get()).data()!;
    expect((d['verified'], d['verificationStatus']), (false, 'rejected'));
  });

  testWidgets('admin approves a pending driver from the queue', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AdminVerificationScreen()));
    await settle(tester);
    expect(find.text('Ramesh'), findsOneWidget);
    expect(find.text('Suresh'), findsNothing);

    await tester.tap(find.text('Approve'));
    await settle(tester);
    expect(find.text('Ramesh'), findsNothing);
    expect(find.text('No drivers in this list'), findsOneWidget);

    await tester.tap(find.text('Approved'));
    await settle(tester);
    expect(find.text('Ramesh'), findsOneWidget);
    expect(find.text('Suresh'), findsOneWidget);
  });
}
