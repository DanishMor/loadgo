import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/business.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/business_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/customer/business_invites_card.dart';
import 'package:transport_app/customer/business_statement_screen.dart';

import 'test_utils.dart';

Booking trip(String id, DateTime at, int paise, {String? center, String status = 'delivered'}) => Booking(
      id: id, loadId: id, driverId: 'd', vehicleId: 'v', customerId: 'c', status: status, pickup: 'Pune', drop: 'Delhi, North', cargoType: 'x', weight: 1,
      vehicleType: '20ft', budget: null, pickupDate: null, notes: '', vehicleNumber: 'MH12AB1', driverName: 'D', driverPhone: '1',
      timeline: {status: at}, agreedFarePaise: paise, costCenter: center, businessId: 'o1',
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

  group('statement maths', () {
    final trips = [
      trip('a', DateTime(2026, 9, 3), 100000, center: 'Plant 2'),
      trip('b', DateTime(2026, 9, 20), 250050, center: 'Plant 2'),
      trip('c', DateTime(2026, 9, 21), 70000, center: 'Sales'),
      trip('d', DateTime(2026, 9, 25), 5000),
      trip('e', DateTime(2026, 10, 1), 999900, center: 'Plant 2'),
      trip('f', DateTime(2026, 9, 5), 888800, center: 'Sales', status: 'cancelled'),
    ];

    test('only delivered trips of the month, grouped by cost centre', () {
      final s = MonthlyStatement.from(trips, DateTime(2026, 9));
      expect((s.month, s.trips, s.totalPaise), ('2026-09', 4, 425050));
      expect(s.byCostCenter, {'Plant 2': 350050, 'Sales': 70000, '': 5000});
      expect(s.sortedCenters.map((e) => e.key), ['Plant 2', 'Sales', '']);
      expect(MonthlyStatement.from(trips, DateTime(2026, 8)).trips, 0);
    });

    test('CSV has one quoted row per trip with rupees', () {
      final csv = MonthlyStatement.from(trips, DateTime(2026, 9)).toCsv().split('\n');
      expect(csv.first, 'date,cost_center,from,to,vehicle,amount_rupees');
      expect(csv, hasLength(5));
      expect(csv[1], '2026-09-03,"Plant 2","Pune","Delhi, North","MH12AB1",1000.00');
      expect(csv[2], endsWith(',2500.50'));
      expect(csv.last, '2026-09-25,"","Pune","Delhi, North","MH12AB1",50.00');
    });
  });

  test('invite, booker joins, posts a load with the company id and cost centre that reaches the booking', () async {
    await db.collection('users').doc('o1').set({'role': 'customer', 'name': 'Owner', 'phone': '+919800000001', 'business': {'legalName': 'Acme Ltd'}});
    await db.collection('users').doc('b1').set({'role': 'customer', 'name': 'Bina'});
    await expectLater(BusinessService.invite('123'), throwsA(isA<BusinessTeamException>().having((e) => e.reason, 'r', 'phone')));
    await expectLater(BusinessService.invite('9800000001'), throwsA(isA<BusinessTeamException>().having((e) => e.reason, 'r', 'own_phone')));
    final id = await BusinessService.invite('98765 43210');
    await expectLater(BusinessService.invite('9876543210'), throwsA(isA<BusinessTeamException>().having((e) => e.reason, 'r', 'already_member')));

    signIn('b1', '+919876543210');
    expect(await BusinessService.postingBusinessId(), isNull);
    final inv = (await BusinessService.watchMyInvites().first).single;
    expect((inv.id, inv.ownerName), (id, 'Acme Ltd'));
    await BusinessService.respond(inv, accept: true);
    expect(await BusinessService.postingBusinessId(), 'o1');

    final loadId = await LoadService.post(
      pickup: 'Pune', drop: 'Delhi', cargoType: 'FMCG', weight: 5, vehicleType: '20ft', budget: 20000,
      pickupDate: DateTime.now().add(const Duration(days: 2)), notes: '', businessId: 'o1', costCenter: ' Plant 2 ',
    );
    final load = Load.fromDoc(await db.collection('loads').doc(loadId).get());
    expect((load.businessId, load.costCenter, load.shipperId), ('o1', 'Plant 2', 'b1'));
    expect(() => LoadService.post(pickup: 'Pune', drop: 'Delhi', cargoType: 'FMCG', weight: 5, vehicleType: '20ft', budget: null, pickupDate: DateTime.now(), notes: '', costCenter: 'x' * 31), throwsArgumentError);

    await db.collection('users').doc('d1').set({'role': 'driver', 'driverName': 'Ramesh', 'phone': '+919811111111', 'verified': true});
    signIn('d1', '+919811111111');
    final v = await VehicleService.add(number: 'MH12AB1234', type: '20ft', capacity: 10, rcNumber: 'RC1');
    final vehicle = (await VehicleService.fetchMyActive()).firstWhere((x) => x.id == v);
    final bookingId = await BookingService.accept(loadId: loadId, vehicle: vehicle);
    final b = Booking.fromDoc(await db.collection('bookings').doc(bookingId).get());
    expect((b.businessId, b.costCenter), ('o1', 'Plant 2'));

    signIn('o1', '+919800000001');
    expect((await BusinessService.watchCompanyBookings().first).single.id, bookingId);
    expect((await BusinessService.watchMembers().first).single.memberName, 'Bina');

    await BusinessService.saveStatement(MonthlyStatement.from([trip('a', DateTime(2026, 9, 3), 100000, center: 'Plant 2'), trip('z', DateTime(2026, 9, 4), 5000)], DateTime(2026, 9)));
    final saved = (await db.collection('business_statements').doc('o1_2026-09').get()).data()!;
    expect((saved['trips'], saved['totalPaise']), (2, 105000));
    expect(Map<String, dynamic>.from(saved['byCostCenter'] as Map), {'Plant 2': 100000, '-': 5000});
    expect((await BusinessService.watchSavedStatements().first).single['month'], '2026-09');

    // the owner removes the booker: no more company id for their loads
    await BusinessService.removeMember((await BusinessService.watchMembers().first).single);
    signIn('b1', '+919876543210');
    expect(await BusinessService.postingBusinessId(), isNull);
  });

  test('an owner without a company name cannot invite; a driver account cannot join', () async {
    await db.collection('users').doc('o1').set({'role': 'customer', 'phone': '+919800000001'});
    await expectLater(BusinessService.invite('9876543210'), throwsA(isA<BusinessTeamException>().having((e) => e.reason, 'r', 'no_company')));
    await db.collection('users').doc('o1').set({'business': {'legalName': 'Acme'}}, SetOptions(merge: true));
    await BusinessService.invite('9876543210');
    await db.collection('users').doc('d1').set({'role': 'driver'});
    signIn('d1', '+919876543210');
    final inv = (await BusinessService.watchMyInvites().first).single;
    await expectLater(BusinessService.respond(inv, accept: true), throwsA(isA<BusinessTeamException>().having((e) => e.reason, 'r', 'not_customer')));
  });

  testWidgets('statement screen: month, totals, cost centres, save', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(
        home: BusinessStatementScreen(
          now: () => DateTime(2026, 9, 28),
          bookings: Stream.value([trip('a', DateTime(2026, 9, 3), 100000, center: 'Plant 2'), trip('c', DateTime(2026, 9, 21), 70000), trip('e', DateTime(2026, 10, 1), 999900)]),
        ),
      ),
    ));
    await settle(tester);
    expect(find.text('2026-09'), findsOneWidget);
    expect(find.byKey(const ValueKey('center_Plant 2')), findsOneWidget);
    expect(find.byKey(const ValueKey('center_')), findsOneWidget);
    expect(find.text('No cost centre'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('stmtSave')));
    await settle(tester);
    expect((await tester.runAsync(() => db.collection('business_statements').doc('o1_2026-09').get()))!.data()!['totalPaise'], 170000);
    await tester.tap(find.byKey(const ValueKey('stmtNext')));
    await settle(tester);
    expect(find.text('2026-10'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('stmtNext')));
    await settle(tester);
    expect(find.text('No delivered trips this month'), findsOneWidget);
  });

  testWidgets('customer card: join a company', (tester) async {
    await db.collection('users').doc('o1').set({'role': 'customer', 'phone': '+919800000001', 'business': {'legalName': 'Acme'}});
    await db.collection('users').doc('b1').set({'role': 'customer', 'name': 'Bina'});
    await BusinessService.invite('9876543210');
    signIn('b1', '+919876543210');
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: Scaffold(body: BusinessInvitesCard()))));
    await settle(tester);
    expect(find.text('Acme invited you to book loads for their company'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bizJoin_o1_919876543210')));
    await settle(tester);
    expect((await tester.runAsync(() => db.collection('business_members').doc('o1_b1').get()))!.exists, isTrue);
  });
}
