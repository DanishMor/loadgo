import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/fleet.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/fleet_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/driver/fleet_invites_card.dart';
import 'package:transport_app/fleet/fleet_dashboard.dart';

import 'test_utils.dart';

Vehicle veh(String id, {String? driver, String availability = 'available'}) =>
    Vehicle(id: id, ownerId: 'o1', number: 'MH12AB$id', type: '20ft', capacity: 10, rcNumber: 'R', status: 'active', availability: availability, assignedDriverId: driver);

Booking book(String vehicleId, String status, {int paise = 0, DateTime? at}) => Booking(
      id: '$vehicleId$status$paise', loadId: 'l', driverId: 'd1', vehicleId: vehicleId, customerId: 'c', status: status, pickup: 'A', drop: 'B', cargoType: 'x',
      weight: 1, vehicleType: '20ft', budget: null, pickupDate: null, notes: '', vehicleNumber: 'X', driverName: 'D', driverPhone: '1', timeline: {status: at ?? DateTime(2026, 10, 4, 9)},
      agreedFarePaise: paise,
    );

void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth current;
  final people = <String, MockFirebaseAuth>{};
  void signIn(String uid, String phone) =>
      current = people.putIfAbsent(uid, () => MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid, phoneNumber: phone)));

  setUp(() {
    db = FakeFirebaseFirestore();
    people.clear();
    signIn('o1', '+919800000001');
    Backend.useFakes(db: db, uid: () => current.currentUser?.uid, auth: () => current);
    languageNotifier.value = AppLanguage.english;
  });

  test('phone numbers are normalised and checked', () {
    expect(FleetInvite.normalisePhone('98765 43210'), '+919876543210');
    expect(FleetInvite.normalisePhone('+91 98765-43210'), '+919876543210');
    expect(FleetInvite.normalisePhone('09876543210'), '+919876543210');
    expect(FleetInvite.normalisePhone('1234567890'), isNull);
    expect(FleetInvite.normalisePhone('98765'), isNull);
    expect(FleetInvite.idFor('o1', '+919876543210'), 'o1_919876543210');
  });

  test('invite, driver joins, owner assigns a vehicle, member removal frees it', () async {
    await db.collection('users').doc('o1').set({'role': 'fleet', 'name': 'Sunil', 'phone': '+919800000001'});
    await db.collection('users').doc('d1').set({'role': 'driver', 'driverName': 'Ramesh'});
    await db.collection('vehicles').doc('v1').set({'ownerId': 'o1', 'number': 'MH12AB1', 'type': '20ft', 'capacity': 10, 'status': 'active', 'availability': 'available'});

    await expectLater(FleetService.invite('123'), throwsA(isA<FleetException>().having((e) => e.reason, 'r', 'phone')));
    await expectLater(FleetService.invite('9800000001'), throwsA(isA<FleetException>().having((e) => e.reason, 'r', 'own_phone')));
    final id = await FleetService.invite('98765 43210');
    expect(id, 'o1_919876543210');
    await expectLater(FleetService.invite('9876543210'), throwsA(isA<FleetException>().having((e) => e.reason, 'r', 'already_member')));
    expect((await FleetService.watchInvitesSent().first).single.status, 'pending');

    signIn('d1', '+919876543210');
    final mine = await FleetService.watchMyInvites().first;
    expect(mine.single.ownerName, 'Sunil');
    await FleetService.respond(mine.single, accept: true);
    expect(await FleetService.watchMyInvites().first, isEmpty);
    expect((await FleetService.watchMyFleets().first).single.ownerName, 'Sunil');

    signIn('o1', '+919800000001');
    final members = await FleetService.watchMembers().first;
    expect((members.single.driverName, members.single.driverPhone, members.single.active), ('Ramesh', '+919876543210', true));
    await VehicleService.assignDriver('v1', 'd1');

    signIn('d1', '+919876543210');
    expect((await VehicleService.fetchMyActive()).map((v) => v.id), ['v1']);
    expect((await VehicleService.watchMine().first).single.assignedDriverId, 'd1');

    signIn('o1', '+919800000001');
    await FleetService.removeMember(members.single, vehicleIds: ['v1']);
    expect((await db.collection('vehicles').doc('v1').get()).data()!.containsKey('assignedDriverId'), isFalse);
    expect(await FleetService.watchMembers().first.then((m) => m.single.active), isFalse);
    signIn('d1', '+919876543210');
    expect(await VehicleService.fetchMyActive(), isEmpty);
    // a declined invite can be sent again
    signIn('o1', '+919800000001');
    await FleetService.cancelInvite(id);
    await FleetService.invite('9876543210');
  });

  test('a customer account cannot join a fleet; declining records the answer', () async {
    await db.collection('users').doc('o1').set({'role': 'fleet', 'name': 'Sunil'});
    await db.collection('users').doc('c1').set({'role': 'customer'});
    await FleetService.invite('9876543210');
    signIn('c1', '+919876543210');
    final invite = (await FleetService.watchMyInvites().first).single;
    await expectLater(FleetService.respond(invite, accept: true), throwsA(isA<FleetException>().having((e) => e.reason, 'r', 'not_driver')));
    await FleetService.respond(invite, accept: false);
    expect((await db.collection('fleet_invites').doc(invite.id).get()).data()!['status'], 'declined');
    expect(await db.collection('fleet_members').get().then((s) => s.docs), isEmpty);
  });

  test('summary: earnings per vehicle, today, trips on the road, idle vehicles, drivers', () {
    final now = DateTime(2026, 10, 4, 18);
    final s = FleetSummary.from(
      vehicles: [veh('1', driver: 'd1'), veh('2'), veh('3', availability: 'maintenance')],
      bookings: [
        book('1', 'delivered', paise: 500000, at: DateTime(2026, 10, 4, 10)),
        book('1', 'delivered', paise: 300000, at: DateTime(2026, 10, 2, 10)),
        book('1', 'in_transit'),
        book('2', 'delivered', paise: 100000, at: DateTime(2026, 9, 1)),
        book('2', 'cancelled'),
      ],
      members: const [FleetMember(id: 'o1_d1', ownerId: 'o1', driverId: 'd1', driverName: 'Ramesh', active: true), FleetMember(id: 'o1_d2', ownerId: 'o1', driverId: 'd2', active: false)],
      now: now,
    );
    expect(s.totalEarningsPaise, 900000);
    expect(s.todayEarningsPaise, 500000);
    expect(s.activeTrips, 1);
    expect(s.idleVehicles, 1); // vehicle 2 only: 1 is on a trip, 3 is in maintenance
    expect(s.activeDrivers, 1);
    expect(s.vehicles.first.vehicle.id, '1');
    expect(s.vehicles.first.driverName, 'Ramesh');
    expect(s.vehicles.first.deliveredTrips, 2);
  });

  testWidgets('dashboard shows the figures', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(
        home: Scaffold(
          body: FleetDashboard(
            now: () => DateTime(2026, 10, 4, 18),
            vehicles: Stream.value([veh('1', driver: 'd1'), veh('2')]),
            bookings: Stream.value([book('1', 'delivered', paise: 500000, at: DateTime(2026, 10, 4, 10)), book('1', 'in_transit')]),
            members: Stream.value(const [FleetMember(id: 'o1_d1', ownerId: 'o1', driverId: 'd1', driverName: 'Ramesh', active: true)]),
          ),
        ),
      ),
    ));
    await settle(tester);
    expect(tester.widget<Text>(find.byKey(const ValueKey('statVehicles'))).data, '2');
    expect(tester.widget<Text>(find.byKey(const ValueKey('statActive'))).data, '1');
    expect(tester.widget<Text>(find.byKey(const ValueKey('statIdle'))).data, '1');
    expect(tester.widget<Text>(find.byKey(const ValueKey('statDrivers'))).data, '1');
    expect(find.byKey(const ValueKey('fleetRow_1')), findsOneWidget);
    expect(find.textContaining('Ramesh'), findsWidgets);
  });

  testWidgets('driver card: join an invite', (tester) async {
    await db.collection('users').doc('o1').set({'role': 'fleet', 'name': 'Sunil'});
    await db.collection('users').doc('d1').set({'role': 'driver', 'driverName': 'Ramesh'});
    await FleetService.invite('9876543210');
    signIn('d1', '+919876543210');
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: Scaffold(body: FleetInvitesCard()))));
    await settle(tester);
    expect(find.text('Sunil invited you to their fleet'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('join_o1_919876543210')));
    await settle(tester);
    expect((await tester.runAsync(() => db.collection('fleet_members').doc('o1_d1').get()))!.exists, isTrue);
  });

  test('a fleet driver accepting a load stamps the owner on the booking', () async {
    await db.collection('users').doc('d1').set({'role': 'driver', 'driverName': 'Ramesh', 'phone': '+919876543210', 'verified': true});
    await db.collection('vehicles').doc('v1').set({'ownerId': 'o1', 'assignedDriverId': 'd1', 'number': 'MH12AB1', 'type': '20ft', 'capacity': 10, 'status': 'active', 'availability': 'available'});
    await db.collection('loads').doc('l1').set({
      'shipperId': 'c1', 'pickup': 'Pune', 'drop': 'Delhi', 'cargoType': 'x', 'weight': 5, 'vehicleType': '20ft', 'status': 'open', 'createdAt': Timestamp.now(),
    });
    signIn('d1', '+919876543210');
    final v = (await VehicleService.fetchMyActive()).single;
    final id = await BookingService.accept(loadId: 'l1', vehicle: v);
    expect((await db.collection('bookings').doc(id).get()).data()!['fleetOwnerId'], 'o1');
  });
}
