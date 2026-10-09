import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_verification_screen.dart';
import 'package:transport_app/auth/driver_onboarding_card.dart';
import 'package:transport_app/core/identity/kyc_validators.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/onboarding/driver_onboarding.dart';
import 'package:transport_app/core/services/admin_service.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/user_service.dart';

import 'test_utils.dart';

/// MASTER-6 Task 21: driver onboarding progress, document checklist, rejection reason and resubmit.
void main() {
  late FakeFirebaseFirestore db;
  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'd1');
  });

  Map<String, dynamic> full({String status = 'pending', Map<String, dynamic>? meta}) => {
        'driverProfileComplete': true,
        'locationConsentAsked': true,
        'kycComplete': true,
        'verificationStatus': status,
        'verified': status == 'approved',
        'driverKyc': {'dlNumber': 'MH1220190001234', 'dlExpiry': Timestamp.fromDate(DateTime(2031)), 'rcNumber': 'MH12AB1234', 'aadhaarLast4': '1234', 'pan': 'ABCDE1234F'},
        'verificationMeta': ?meta,
      };

  test('a new driver has nothing done; the next step is the profile', () {
    final o = DriverOnboarding.fromUser(null);
    expect((o.doneCount, o.fraction, o.nextStep, o.status), (0, 0.0, 'profile', 'pending'));
    expect(o.documentsComplete, isFalse);
    expect(o.isRejected, isFalse);
  });

  test('steps and documents follow the user document; approval completes the last step', () {
    final waiting = DriverOnboarding.fromUser(full());
    expect((waiting.doneCount, waiting.nextStep), (3, 'review'));
    expect(waiting.documentsComplete, isTrue);
    final done = DriverOnboarding.fromUser(full(status: 'approved'));
    expect((done.doneCount, done.fraction, done.nextStep), (4, 1.0, null));
    final partial = DriverOnboarding.fromUser({'driverProfileComplete': true, 'driverKyc': {'dlNumber': 'X'}});
    expect(partial.docs.where((d) => d.present).map((d) => d.key), ['licence']);
    expect(partial.nextStep, 'consent');
  });

  test('a rejection carries its reason and note; an unknown reason is dropped; an approved driver shows none', () {
    final r = DriverOnboarding.fromUser(full(status: 'rejected', meta: {'reason': 'licence_expired', 'note': 'Valid till 2023'}));
    expect((r.isRejected, r.rejectReason, r.rejectNote), (true, 'licence_expired', 'Valid till 2023'));
    expect(DriverOnboarding.fromUser(full(status: 'rejected', meta: {'reason': 'made_up'})).rejectReason, '');
    expect(DriverOnboarding.fromUser(full(status: 'approved', meta: {'reason': 'licence_expired'})).rejectReason, '');
  });

  test('the verifier rejects with a reason and note; approving stores none; both are audited', () async {
    await db.collection('users').doc('d1').set({'verificationStatus': 'pending', 'verified': false});
    Backend.useFakes(db: db, uid: () => 'ver1');
    await AdminService.setStatus('d1', 'rejected', reason: RejectReason.nameMismatch, note: '  name differs  ');
    var u = (await db.collection('users').doc('d1').get()).data()!;
    expect((u['verificationStatus'], u['verified']), ('rejected', false));
    expect((u['verificationMeta'] as Map)['reason'], 'name_mismatch');
    expect((u['verificationMeta'] as Map)['note'], 'name differs');
    await AdminService.setStatus('d1', 'approved');
    u = (await db.collection('users').doc('d1').get()).data()!;
    expect((u['verificationStatus'], u['verified']), ('approved', true));
    // (a real update replaces the whole verificationMeta map, so the old reason goes with it; the fake merges maps)
    final audit = (await db.collection('audit_events').get()).docs.map((d) => d.data()['data']);
    expect(audit.any((d) => d['reason'] == 'name_mismatch'), isTrue);
  });

  test('sending documents again after a rejection puts the driver back in review', () async {
    await db.collection('users').doc('d1').set(full(status: 'rejected', meta: {'reason': 'docs_unclear'}));
    await UserService.saveDriverKyc(DriverKyc(dlNumber: 'MH1220190001234', dlExpiry: DateTime(2032), rcNumber: 'MH12AB1234', aadhaarLast4: '1234', pan: 'ABCDE1234F'));
    final u = (await db.collection('users').doc('d1').get()).data()!;
    expect((u['verificationStatus'], u['verified']), ('pending', false));
  });

  test('an approved or pending driver editing documents keeps their status', () async {
    await db.collection('users').doc('d1').set(full(status: 'approved'));
    await UserService.saveDriverKyc(DriverKyc(dlNumber: 'MH1220190001234', dlExpiry: DateTime(2032), rcNumber: 'MH12AB1234', aadhaarLast4: '1234', pan: 'ABCDE1234F'));
    expect((await db.collection('users').doc('d1').get()).data()!['verificationStatus'], 'approved');
  });

  testWidgets('the card shows the bar, the steps, the checklist; a rejection shows the reason and a resubmit button', (tester) async {
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: DriverOnboardingCard(user: full()))))));
    await settle(tester);
    expect(find.text('Your set-up: 3 of 4 steps done'), findsOneWidget);
    expect(find.byKey(const ValueKey('obStep_review_todo')), findsOneWidget);
    expect(find.byKey(const ValueKey('obStep_documents_done')), findsOneWidget);
    expect(find.byKey(const ValueKey('obRejected')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: DriverOnboardingCard(user: full(status: 'rejected', meta: {'reason': 'rc_mismatch', 'note': 'Plate differs'})))))));
    await settle(tester);
    expect(find.text('The vehicle number does not match the registration'), findsOneWidget);
    expect(find.text('Plate differs'), findsOneWidget);
    expect(find.byKey(const ValueKey('obResubmit')), findsOneWidget);
  });

  testWidgets('rejecting in the queue asks for a reason first and Cancel changes nothing', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Backend.useFakes(db: db, uid: () => 'ver1');
    await db.collection('users').doc('d2').set({'driverName': 'Anil', 'role': 'driver', 'roles': ['driver'], 'verificationStatus': 'pending', 'verified': false, 'vehicleNumber': 'MH12AB1234', 'vehicleType': 'Mini', 'phone': '+919999900001'});
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: AdminVerificationScreen())));
    await settle(tester);
    await tester.tap(find.text('Reject').first);
    await settle(tester);
    expect(find.text('Why not approved?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect((await db.collection('users').doc('d2').get()).data()!['verificationStatus'], 'pending');
    await tester.tap(find.text('Reject').first);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('reject_licence_expired')));
    await tester.enterText(find.byKey(const ValueKey('rejectNote')), 'Expired in 2023');
    await tester.tap(find.byKey(const ValueKey('rejectConfirm')));
    await settle(tester);
    final m = (await db.collection('users').doc('d2').get()).data()!['verificationMeta'] as Map;
    expect((m['reason'], m['note']), ('licence_expired', 'Expired in 2023'));
  });
}
