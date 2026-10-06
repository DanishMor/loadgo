import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/l10n/help_strings.dart';
import 'package:transport_app/core/services/account_deletion_service.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/settings/help_screen.dart';
import 'package:transport_app/core/settings/legal_screens.dart';
import 'package:transport_app/core/settings/onboarding_screen.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  const hash = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'u1');
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> seedAccount({String? tier}) async {
    await db.collection('users').doc('u1').set({'role': 'driver', 'identityHashes': {'dl': hash}, 'riskTier': ?tier});
    await db.collection('identity_index').doc(hash).set({'uid': 'u1', 'type': 'dl'});
    await db.collection('identity_index').doc('other').set({'uid': 'u2', 'type': 'dl'});
    await db.collection('users').doc('u1').collection('saved_places').doc('p').set({'label': 'x'});
    await db.collection('notifications').add({'userId': 'u1'});
    await db.collection('notifications').add({'userId': 'u2'});
    await db.collection('vehicles').doc('v1').set({'ownerId': 'u1', 'number': 'MH12AB1234'});
    await db.collection('vehicle_numbers').doc('MH12AB1234').set({'ownerId': 'u1'});
    await db.collection('loads').doc('L1').set({'shipperId': 'u1', 'status': 'open'});
    await db.collection('loads').doc('L2').set({'shipperId': 'u1', 'status': 'matched'});
  }

  test('deletion removes profile, private data, vehicles, open loads and identity entries, then the Auth user', () async {
    await seedAccount();
    var authDeleted = false;
    await AccountDeletionService.deleteAccount(deleteAuthUser: () async => authDeleted = true);
    expect(authDeleted, isTrue);
    expect((await db.collection('users').doc('u1').get()).exists, isFalse);
    expect((await db.collection('identity_index').doc(hash).get()).exists, isFalse);
    expect((await db.collection('identity_index').doc('other').get()).exists, isTrue);
    expect((await db.collection('users').doc('u1').collection('saved_places').get()).docs, isEmpty);
    expect((await db.collection('notifications').get()).docs.length, 1);
    expect((await db.collection('vehicles').doc('v1').get()).exists, isFalse);
    expect((await db.collection('vehicle_numbers').doc('MH12AB1234').get()).exists, isFalse);
    expect((await db.collection('loads').doc('L1').get()).exists, isFalse);
    expect((await db.collection('loads').doc('L2').get()).exists, isTrue);
  });

  test('active trips and restricted accounts block deletion and nothing is deleted', () async {
    await seedAccount();
    await db.collection('bookings').add({'customerId': 'u9', 'driverId': 'u1', 'status': 'in_transit'});
    var authDeleted = false;
    await expectLater(AccountDeletionService.deleteAccount(deleteAuthUser: () async => authDeleted = true), throwsA(isA<ActiveTripsException>()));
    expect(authDeleted, isFalse);
    expect((await db.collection('users').doc('u1').get()).exists, isTrue);

    await db.collection('bookings').get().then((s) => s.docs.first.reference.update({'status': 'delivered'}));
    await db.collection('users').doc('u1').update({'riskTier': 'banned'});
    await expectLater(AccountDeletionService.deleteAccount(deleteAuthUser: () async {}), throwsA(isA<AccountRestrictedException>()));
    expect((await db.collection('identity_index').doc(hash).get()).exists, isTrue);
  });

  test('every help string has 12 languages', () {
    for (final e in helpStrings.entries) {
      expect(e.value.length, 12, reason: e.key);
      expect(e.value.every((s) => s.trim().isNotEmpty), isTrue, reason: e.key);
    }
  });

  testWidgets('help screen lists the FAQ and opens a policy', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: HelpScreen()));
    await settle(tester);
    expect(find.byKey(const ValueKey('faq1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('faq1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Open Post Load'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: PolicyScreen.refund));
    await settle(tester);
    expect(find.textContaining('Placeholder'), findsNothing);
  });

  testWidgets('onboarding: skip marks it seen and calls onDone', (tester) async {
    var done = false;
    expect(await OnboardingStore.seen(), isFalse);
    await tester.pumpWidget(MaterialApp(home: OnboardingScreen(onDone: () => done = true)));
    await settle(tester);
    await tester.tap(find.text('Skip'));
    await settle(tester);
    expect(done, isTrue);
    expect(await OnboardingStore.seen(), isTrue);
  });
}
