import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/onboarding/transporter_onboarding.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/fleet_service.dart';
import 'package:transport_app/core/services/transporter_service.dart';
import 'package:transport_app/core/transporter/transporter_logic.dart';
import 'package:transport_app/fleet/transporter_onboarding_card.dart';

import 'test_utils.dart';

/// MASTER-6 Task 27: transporter onboarding polish and the fleet attach / invite flow.
void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth current;
  final people = <String, MockFirebaseAuth>{};
  void signIn(String uid, String phone) =>
      current = people.putIfAbsent(uid, () => MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid, phoneNumber: phone)));

  setUp(() {
    db = FakeFirebaseFirestore();
    people.clear();
    signIn('tr1', '+919800000001');
    Backend.useFakes(db: db, uid: () => current.currentUser?.uid, auth: () => current);
  });

  Map<String, dynamic> user({bool profile = true, String status = 'pending', Map<String, dynamic>? meta, String gstin = '', String city = 'Pune', List<String> routes = const ['Pune-Delhi']}) => {
        'fleetProfileComplete': profile,
        'verificationStatus': status,
        'verified': status == 'approved',
        'fleet': {'officeCity': city, 'routes': routes},
        if (gstin.isNotEmpty) 'business': {'gstin': gstin},
        'verificationMeta': ?meta,
      };

  test('steps: profile, company details, a vehicle, a driver, the review', () {
    final none = TransporterOnboarding.fromUser(null, vehicles: 0, members: 0);
    expect((none.doneCount, none.nextStep), (0, 'profile'));
    final o = TransporterOnboarding.fromUser(user(), vehicles: 0, members: 0);
    expect((o.doneCount, o.nextStep), (2, 'vehicle')); // the profile and the company details (city + routes)
    final withGst = TransporterOnboarding.fromUser(user(city: '', routes: const [], gstin: '27ABCDE1234F1Z5'), vehicles: 1, members: 0);
    expect((withGst.doneCount, withGst.nextStep), (3, 'driver'));
    final noCompany = TransporterOnboarding.fromUser(user(city: '', routes: const []), vehicles: 1, members: 1);
    expect(noCompany.steps.firstWhere((s) => s.key == 'company').done, isFalse);
    final done = TransporterOnboarding.fromUser(user(status: 'approved'), vehicles: 2, members: 3);
    expect((done.complete, done.fraction, done.nextStep), (true, 1.0, null));
  });

  test('a rejection carries its reason and note; an unknown reason is dropped', () {
    final r = TransporterOnboarding.fromUser(user(status: 'rejected', meta: {'reason': 'name_mismatch', 'note': 'Company name differs'}), vehicles: 0, members: 0);
    expect((r.isRejected, r.rejectReason, r.rejectNote), (true, 'name_mismatch', 'Company name differs'));
    expect(TransporterOnboarding.fromUser(user(status: 'rejected', meta: {'reason': 'x'}), vehicles: 0, members: 0).rejectReason, '');
  });

  test('correcting the profile after a rejection sends it back to review; an approved profile keeps its status', () async {
    await db.collection('users').doc('tr1').set({'role': 'fleet', 'companyName': 'Old', 'verificationStatus': 'rejected', 'verified': false, 'fleet': {'pan': 'ABCDE1234F', 'officeCity': 'Pune', 'routes': ['Pune-Delhi'], 'vehicleTypes': ['20ft'], 'vehicleCount': 3}});
    final p = TransporterProfile(pan: 'ABCDE1234F', company: 'Acme Roadways', officeCity: 'Pune', routes: ['Pune-Delhi'], vehicleTypes: ['20ft'], vehicleCount: 3);
    await TransporterService.updateProfile(p);
    var u = (await db.collection('users').doc('tr1').get()).data()!;
    expect((u['verificationStatus'], u['verified'], u['companyName']), ('pending', false, 'Acme Roadways'));
    await db.collection('users').doc('tr1').update({'verificationStatus': 'approved', 'verified': true});
    await TransporterService.updateProfile(p);
    u = (await db.collection('users').doc('tr1').get()).data()!;
    expect(u['verificationStatus'], 'approved');
  });

  test('attach flow: a vehicle counts only while its driver is an active member; leaving detaches it', () async {
    await db.collection('users').doc('tr1').set({'role': 'fleet', 'name': 'Sunil', 'phone': '+919800000001'});
    await db.collection('users').doc('d1').set({'role': 'driver', 'driverName': 'Ramesh'});
    await db.collection('vehicles').doc('dv1').set({'ownerId': 'd1', 'number': 'KA01CD5678', 'type': '14ft', 'capacity': 4, 'status': 'active', 'availability': 'available'});
    await db.collection('vehicles').doc('dv2').set({'ownerId': 'd1', 'number': 'KA01CD9999', 'type': '14ft', 'capacity': 4, 'status': 'active', 'availability': 'available'});
    await FleetService.invite('9876543210');
    signIn('d1', '+919876543210');
    final invite = (await FleetService.watchMyInvites().first).single;
    await FleetService.respond(invite, accept: true);
    await TransporterService.setAttached('dv1', 'tr1');
    await TransporterService.setAttached('dv2', 'tr1');
    signIn('tr1', '+919800000001');
    expect({for (final v in await TransporterService.watchAttached().first) v.id}, {'dv1', 'dv2'});
    // the transporter removes the driver: the vehicles stop counting even though they stay marked
    final member = (await FleetService.watchMembers().first).single;
    await FleetService.removeMember(member);
    expect(await TransporterService.watchAttached().first, isEmpty);
    expect((await db.collection('vehicles').doc('dv1').get()).data()!['attachedTo'], 'tr1');
  });

  test('attach flow: the driver leaving the fleet detaches their vehicles from it, and only from it', () async {
    await db.collection('users').doc('tr1').set({'role': 'fleet', 'name': 'Sunil'});
    await db.collection('users').doc('tr2').set({'role': 'fleet', 'name': 'Other'});
    await db.collection('users').doc('d1').set({'role': 'driver', 'driverName': 'Ramesh'});
    await db.collection('vehicles').doc('a').set({'ownerId': 'd1', 'number': 'KA01CD1111', 'type': '14ft', 'capacity': 4, 'status': 'active', 'availability': 'available', 'attachedTo': 'tr1'});
    await db.collection('vehicles').doc('b').set({'ownerId': 'd1', 'number': 'KA01CD2222', 'type': '14ft', 'capacity': 4, 'status': 'active', 'availability': 'available', 'attachedTo': 'tr2'});
    await db.collection('vehicles').doc('c').set({'ownerId': 'zz', 'number': 'KA01CD3333', 'type': '14ft', 'capacity': 4, 'status': 'active', 'availability': 'available', 'attachedTo': 'tr1'});
    await db.collection('fleet_members').doc('tr1_d1').set({'ownerId': 'tr1', 'ownerName': 'Sunil', 'driverId': 'd1', 'driverName': 'Ramesh', 'driverPhone': '+919876543210', 'active': true});
    signIn('d1', '+919876543210');
    final m = (await FleetService.watchMyFleets().first).single;
    await FleetService.leave(m);
    expect((await db.collection('vehicles').doc('a').get()).data()!.containsKey('attachedTo'), isFalse);
    expect((await db.collection('vehicles').doc('b').get()).data()!['attachedTo'], 'tr2');
    expect((await db.collection('vehicles').doc('c').get()).data()!['attachedTo'], 'tr1');
    expect((await db.collection('fleet_members').doc('tr1_d1').get()).data()!['active'], false);
  });

  testWidgets('the card shows the steps, offers the next action, and says why after a rejection; it hides when all is done', (tester) async {
    TransporterOnboarding o(Map<String, dynamic> u, {int v = 0, int m = 0}) => TransporterOnboarding.fromUser(u, vehicles: v, members: m);
    Future<void> show(TransporterOnboarding value) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: TransporterOnboardingCard(load: () async => value))))));
      await settle(tester);
    }

    await show(o(user()));
    expect(find.text('Your set-up: 2 of 5 steps done'), findsOneWidget);
    expect(find.byKey(const ValueKey('trObStep_vehicle_todo')), findsOneWidget);
    expect(find.byKey(const ValueKey('trObVehicle')), findsOneWidget);
    expect(find.byKey(const ValueKey('trObRejected')), findsNothing);
    await show(o(user(status: 'rejected', meta: {'reason': 'docs_unclear', 'note': 'GST certificate blurred'}), v: 1, m: 1));
    expect(find.byKey(const ValueKey('trObRejected')), findsOneWidget);
    expect(find.text('A document photo or number is not clear'), findsOneWidget);
    expect(find.text('GST certificate blurred'), findsOneWidget);
    expect(find.byKey(const ValueKey('trObProfile')), findsOneWidget);
    await show(o(user(status: 'approved'), v: 1, m: 1));
    expect(find.byKey(const ValueKey('trOnboarding')), findsNothing);
  });
}
