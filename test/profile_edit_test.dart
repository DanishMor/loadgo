import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/user_service.dart';
import 'package:transport_app/core/profile/profile_view.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;

  setUp(() {
    db = FakeFirebaseFirestore();
  });

  test('driver edits update driverName; blank optional fields are removed', () async {
    Backend.useFakes(db: db, uid: () => 'driver1');
    await db.collection('users').doc('driver1').set({
      'driverName': 'Ramesh', 'name': 'untouched', 'email': 'old@x.com', 'companyName': 'Old Co', 'verified': true,
    });
    await UserService.updateProfile(isDriver: true, name: ' Ramesh Kumar ', email: '', companyName: 'RK Logistics');
    final d = (await db.collection('users').doc('driver1').get()).data()!;
    expect(d['driverName'], 'Ramesh Kumar');
    expect(d['name'], 'untouched');
    expect(d.containsKey('email'), isFalse);
    expect(d['companyName'], 'RK Logistics');
    expect(d['verified'], isTrue, reason: 'verification fields are never touched');
  });

  test('customer edits update name', () async {
    Backend.useFakes(db: db, uid: () => 'customer1');
    await db.collection('users').doc('customer1').set({'name': 'Asha'});
    await UserService.updateProfile(isDriver: false, name: 'Asha Rao', email: 'asha@x.com', companyName: '');
    final d = (await db.collection('users').doc('customer1').get()).data()!;
    expect(d['name'], 'Asha Rao');
    expect(d['email'], 'asha@x.com');
  });

  testWidgets('edit from the profile tab, with validation', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Backend.useFakes(db: db, uid: () => 'customer1');
    await tester.runAsync(() => db.collection('users').doc('customer1').set({'name': 'Asha', 'phone': '+919900000000'}));

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ProfileView(isDriver: false))));
    await settle(tester);
    expect(find.text('Asha'), findsOneWidget);

    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'A');
    await tester.enterText(fields.at(1), 'not-an-email');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Please enter your full name'), findsOneWidget);
    expect(find.text('Please enter a valid email'), findsOneWidget);

    await tester.enterText(fields.at(0), 'Asha Rao');
    await tester.enterText(fields.at(1), 'asha@example.com');
    await tester.enterText(fields.at(2), 'Rao Traders');
    await tester.tap(find.text('Save'));
    await settle(tester);

    // Back on the profile tab with live updates.
    expect(find.text('Asha Rao'), findsOneWidget);
    expect(find.text('asha@example.com'), findsOneWidget);
    expect(find.text('Rao Traders'), findsOneWidget);
  });
}
