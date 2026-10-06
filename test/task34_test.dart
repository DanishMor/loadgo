import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/fleet/fleet_logic.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/matching/load_ranker.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/fleet.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/models/vehicle_expense.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/expense_service.dart';
import 'package:transport_app/core/widgets/common.dart' show formatPaise;
import 'package:transport_app/core/vehicles/vehicle_expenses_screen.dart';
import 'package:transport_app/fleet/fleet_analytics_screen.dart';
import 'package:transport_app/fleet/fleet_dashboard.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth current;
  final people = <String, MockFirebaseAuth>{};
  void signIn(String uid, String phone) =>
      current = people.putIfAbsent(uid, () => MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid, phoneNumber: phone)));
  final now = DateTime(2026, 10, 6, 12);

  setUp(() {
    db = FakeFirebaseFirestore();
    people.clear();
    signIn('o1', '+919800000001');
    Backend.useFakes(db: db, uid: () => current.currentUser?.uid, auth: () => current);
    languageNotifier.value = AppLanguage.english;
  });

  Vehicle veh(String id, {String type = '20ft', num cap = 10, String availability = 'available', String? driver = 'd1', String owner = 'o1'}) =>
      Vehicle(id: id, ownerId: owner, number: 'N$id', type: type, capacity: cap, rcNumber: 'RC', status: 'active', availability: availability, assignedDriverId: driver);

  Booking booking(String id, {String vehicle = 'v1', String status = 'delivered', String customer = 'c1', String driver = 'd1', int fare = 100000, DateTime? accepted, DateTime? delivered, Map<String, Object?>? extra}) {
    final tl = <String, Object?>{
      'accepted': Timestamp.fromDate(accepted ?? now.subtract(const Duration(days: 3))),
      if (status == 'delivered') 'delivered': Timestamp.fromDate(delivered ?? now.subtract(const Duration(days: 2))),
    };
    return Booking.fromMap(id, {
      'customerId': customer, 'driverId': driver, 'status': status, 'agreedFarePaise': fare, 'pickup': 'Pune', 'drop': 'Delhi', 'loadId': 'L$id',
      'vehicleId': vehicle, 'cargoType': 'FMCG', 'weight': 5, 'vehicleType': '20ft', 'notes': '', 'vehicleNumber': 'N$vehicle', 'driverName': 'D', 'driverPhone': '1',
      'timeline': tl, 'paymentStatus': 'pending', ...?extra,
    });
  }

  group('expenses (V10)', () {
    test('add validates, lists newest first, summarises by month and kind, deletes', () async {
      await ExpenseService.add(vehicleId: 'v1', kind: 'fuel', amountPaise: 450000, date: DateTime(2026, 9, 20), now: now);
      await ExpenseService.add(vehicleId: 'v1', kind: 'toll', amountPaise: 30000, note: 'Kherki', date: DateTime(2026, 10, 2), now: now);
      await ExpenseService.add(vehicleId: 'v1', kind: 'fuel', amountPaise: 100000, date: DateTime(2026, 10, 5), now: now);
      final list = await ExpenseService.watchMine().first;
      expect(list.map((e) => e.amountPaise), [100000, 30000, 450000]);
      expect(ExpenseSummary.total(list), 580000);
      expect(ExpenseSummary.byMonth(list), {'2026-10': 130000, '2026-09': 450000});
      expect(ExpenseSummary.byKind(list), {'fuel': 550000, 'toll': 30000});
      expect(ExpenseSummary.lastDays(list, now, 7).length, 2);
      await expectLater(ExpenseService.add(vehicleId: 'v1', kind: 'beer', amountPaise: 5, date: now), throwsArgumentError);
      await expectLater(ExpenseService.add(vehicleId: 'v1', kind: 'fuel', amountPaise: 0, date: now), throwsArgumentError);
      await expectLater(ExpenseService.add(vehicleId: 'v1', kind: 'fuel', amountPaise: VehicleExpense.maxPaise + 1, date: now), throwsArgumentError);
      await expectLater(ExpenseService.add(vehicleId: 'v1', kind: 'fuel', amountPaise: 5, date: DateTime(2020), now: now), throwsArgumentError);
      await ExpenseService.delete(list.first.id);
      expect((await ExpenseService.watchMine().first).length, 2);
    });

    testWidgets('the screen shows totals, adds a line from rupees and shows the empty state', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: VehicleExpensesScreen(vehicleId: 'v1', vehicleNumber: 'MH12AB1234')));
      await settle(tester);
      expect(find.text('No expenses yet'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('exAddButton')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('exAmount')), '1250.50');
      await tester.tap(find.byKey(const ValueKey('exSave')));
      await settle(tester);
      expect(find.byKey(const ValueKey('exTotalText')), findsOneWidget);
      expect(find.textContaining('1,250.50'), findsWidgets);
      expect((await ExpenseService.watchMine().first).single.amountPaise, 125050);
    });
  });

  group('replacement vehicles (V11, SM12)', () {
    test('candidates are free, big enough, not the broken one; same type and smallest first', () {
      final list = replacementCandidates(
        [veh('v1', type: '20ft'), veh('v2', type: '17ft', cap: 8), veh('v3', type: '20ft', cap: 12), veh('v4', type: '20ft', cap: 10), veh('v5', availability: 'on_trip'), veh('v6', cap: 3)],
        weight: 5, preferType: '20ft', excludeId: 'v1', now: now,
      );
      expect(list.map((v) => v.id), ['v4', 'v3', 'v2']);
    });

    test('an expired paper keeps a vehicle out', () {
      final v = Vehicle(id: 'x', ownerId: 'o1', number: 'NX', type: '20ft', capacity: 10, rcNumber: 'R', status: 'active', docs: {'insurance': VehicleDocInfo(number: 'I', expiry: DateTime(2026, 1, 1))});
      expect(replacementCandidates([v], weight: 5, now: now), isEmpty);
    });

    test('replaceVehicle moves the trip, flips availability and records the old vehicle', () async {
      signIn('d1', '+919811111111');
      for (final v in [('v1', 'on_trip'), ('v2', 'available')]) {
        await db.collection('vehicles').doc(v.$1).set({'ownerId': 'd1', 'number': 'N${v.$1}', 'type': '20ft', 'capacity': 10, 'rcNumber': 'R', 'status': 'active', 'availability': v.$2});
      }
      await db.collection('bookings').doc('b1').set({
        'customerId': 'c1', 'driverId': 'd1', 'status': 'in_transit', 'vehicleId': 'v1', 'vehicleNumber': 'Nv1', 'weight': 5, 'pickup': 'Pune', 'drop': 'Delhi',
        'cargoType': 'FMCG', 'vehicleType': '20ft', 'agreedFarePaise': 1, 'loadId': 'L', 'notes': '', 'driverName': 'D', 'driverPhone': '1', 'timeline': {},
        'breakdown': {'note': 'axle', 'replacementRequested': true, 'reportedAt': Timestamp.now()},
      });
      Future<Booking> b() async => Booking.fromDoc(await db.collection('bookings').doc('b1').get());
      Future<Vehicle> v(String id) async => Vehicle.fromDoc(await db.collection('vehicles').doc(id).get());
      await BookingService.replaceVehicle(await b(), await v('v2'), old: await v('v1'));
      final after = await b();
      expect(after.vehicleId, 'v2');
      expect(after.vehicleNumber, 'Nv2');
      expect(after.replacedVehicleIds, ['v1']);
      expect((await v('v2')).availability, 'on_trip');
      expect((await v('v1')).availability, 'maintenance');
      // not a second time without a free vehicle, and not for someone else's trip
      await expectLater(BookingService.replaceVehicle(await b(), await v('v1')), throwsArgumentError);
      signIn('d9', '+919899999999');
      await expectLater(BookingService.replaceVehicle(await b(), await v('v2')), throwsStateError);
    });

    test('without a breakdown request nothing moves', () async {
      signIn('d1', '+919811111111');
      await db.collection('vehicles').doc('v2').set({'ownerId': 'd1', 'number': 'Nv2', 'type': '20ft', 'capacity': 10, 'rcNumber': 'R', 'status': 'active'});
      final plain = booking('b2', status: 'in_transit');
      await expectLater(BookingService.replaceVehicle(plain, await db.collection('vehicles').doc('v2').get().then(Vehicle.fromDoc)), throwsStateError);
    });
  });

  group('fleet allocation (SM9)', () {
    Load load(String id, {String type = '20ft', num w = 5}) =>
        Load(id: id, shipperId: 'c', pickup: 'Pune', drop: 'Delhi', cargoType: 'FMCG', weight: w, vehicleType: type, budget: null, pickupDate: null, notes: '', status: 'open');

    test('each idle vehicle with a driver is suggested once for the first load it fits', () {
      final s = suggestAllocation(
        [load('L1'), load('L2'), load('L3', type: '14ft'), load('L4', w: 50)],
        [veh('v1'), veh('v2', driver: null), veh('v3', cap: 20)],
        now: now,
      );
      expect(s.map((x) => (x.load.id, x.vehicle.id)), [('L1', 'v1'), ('L2', 'v3')]);
      expect(s.first.driverId, 'd1');
    });
  });

  group('fleet analytics (N13, BIZ12)', () {
    final vehicles = [veh('v1'), veh('v2')];
    final bookings = [
      booking('b1', fare: 200000, accepted: now.subtract(const Duration(days: 5)), delivered: now.subtract(const Duration(days: 3))),
      booking('b2', customer: 'c2', fare: 100000, accepted: now.subtract(const Duration(days: 2)), delivered: now.subtract(const Duration(days: 1))),
      booking('b3', customer: 'c1', fare: 50000, vehicle: 'v2', driver: 'd2', accepted: now.subtract(const Duration(days: 10)), delivered: now.subtract(const Duration(days: 9))),
      booking('b4', status: 'cancelled'),
      booking('b5', fare: 999999, accepted: now.subtract(const Duration(days: 60)), delivered: now.subtract(const Duration(days: 59))),
    ];
    final expenses = [
      VehicleExpense(id: 'e1', ownerId: 'o1', vehicleId: 'v1', kind: 'fuel', amountPaise: 60000, date: now.subtract(const Duration(days: 2))),
      VehicleExpense(id: 'e2', ownerId: 'o1', vehicleId: 'v1', kind: 'toll', amountPaise: 1000, date: now.subtract(const Duration(days: 80))),
    ];

    test('30-day window: revenue, expenses, days on the road, customers, drivers', () {
      final a = FleetAnalytics.from(
        vehicles: vehicles, bookings: bookings, expenses: expenses, now: now,
        members: const [FleetMember(id: 'o1_d1', ownerId: 'o1', driverId: 'd1', driverName: 'Ravi', active: true)],
      );
      expect(a.revenuePaise, 350000);
      expect(a.expensesPaise, 60000);
      expect(a.netPaise, 290000);
      final v1 = a.vehicles.firstWhere((r) => r.vehicle.id == 'v1');
      expect(v1.revenuePaise, 300000);
      expect(v1.daysOnRoad, 5); // 5 to 3 days ago (3 days) and 2 to 1 days ago (2 days)
      expect(v1.idleDays, FleetAnalytics.window - v1.daysOnRoad);
      expect(a.customersServed, 2);
      expect(a.repeatCustomers, 1);
      expect(a.topCustomers.first.customerId, 'c1');
      expect(a.topCustomers.first.trips, 2);
      expect(a.tripsPerDriver, {'d1': 2, 'd2': 1});
      expect(a.driverNames['d1'], 'Ravi');
      expect(a.utilisation, greaterThan(0));
    });

    test('maintenance due counts vehicles with service, tyre or papers due within the window', () {
      final due = Vehicle(id: 'v9', ownerId: 'o1', number: 'N9', type: '20ft', capacity: 10, rcNumber: 'R', status: 'active', nextServiceDate: now.add(const Duration(days: 3)));
      final a = FleetAnalytics.from(vehicles: [due, veh('v8')], bookings: const [], expenses: const [], now: now);
      expect(a.maintenanceDue, 1);
      expect(a.utilisation, 0);
    });

    testWidgets('the analytics screen and the dashboard render the figures', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FleetAnalyticsScreen(
            vehicles: Stream.value(vehicles), bookings: Stream.value(bookings), members: Stream.value(const []), expenses: Stream.value(expenses), now: () => now,
          ),
        ),
      ));
      await settle(tester);
      expect(find.byKey(const ValueKey('faRevenue')), findsOneWidget);
      expect(find.text(formatPaise(350000)), findsWidgets);
      expect(find.byKey(const ValueKey('faVehicle_v1')), findsOneWidget);
      expect(find.byKey(const ValueKey('faTop_c1')), findsOneWidget);
    });

    testWidgets('dashboard shows a breakdown with the idle vehicles that can take over and suggested loads', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final broken = booking('bx', vehicle: 'v1', status: 'in_transit', extra: {'breakdown': {'note': 'x', 'replacementRequested': true}});
      final open = Load(id: 'L9', shipperId: 'c', pickup: 'Surat', drop: 'Delhi', cargoType: 'FMCG', weight: 5, vehicleType: '20ft', budget: null, pickupDate: null, notes: '', status: 'open');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FleetDashboard(
            vehicles: Stream.value([veh('v1', availability: 'on_trip'), veh('v2')]), bookings: Stream.value([broken]), members: Stream.value(const []),
            openLoads: Stream.value([open]), now: () => now,
          ),
        ),
      ));
      await settle(tester);
      expect(find.byKey(const ValueKey('breakdownLine_bx')), findsOneWidget);
      expect(find.textContaining('Nv2'), findsWidgets);
      expect(find.byKey(const ValueKey('suggest_L9')), findsOneWidget);
    });
  });

  group('multi-stop route match (SM11)', () {
    const route = PlannedRoute(from: 'Delhi', to: 'Chennai');
    Load withStops(List<String> drops) => Load(
        id: 'L', shipperId: 'c', pickup: 'Delhi', drop: 'Chennai', cargoType: 'FMCG', weight: 5, vehicleType: '20ft', budget: null, pickupDate: null, notes: '',
        status: 'open', extraDrops: drops);

    test('stops inside the corridor of the line count, others do not', () {
      expect(route.stopsAlong(withStops(['Nagpur'])), 1);
      expect(route.stopsAlong(withStops(['Bhopal', 'Mumbai'])), 0);
      expect(route.stopsAlong(withStops(['Nagpur', 'Delhi'])), 2);
      expect(route.stopsAlong(withStops(['Nowhereville'])), 0);
    });

    test('the ranker adds 8 per stop on the route (up to 24) with a reason', () {
      final vehicle = Vehicle(id: 'v', ownerId: 'd', number: 'X', type: '20ft', capacity: 10, rcNumber: 'R', status: 'active');
      DriverContext ctx(PlannedRoute? r) => DriverContext(vehicles: [vehicle], now: now, plannedRoute: r);
      final on = LoadRanker.matchFor(withStops(['Nagpur']), ctx(route))!;
      final off = LoadRanker.matchFor(withStops(['Nagpur']), ctx(null))!;
      expect(on.reasons, contains(MatchReason.stopsOnRoute));
      expect(on.score - off.score, 35 + 8);
      expect(LoadRanker.matchFor(withStops(['Bhopal']), ctx(route))!.reasons, isNot(contains(MatchReason.stopsOnRoute)));
    });
  });
}
