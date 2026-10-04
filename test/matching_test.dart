import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/matching/load_ranker.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/match_service.dart';
import 'package:transport_app/customer/matching_vehicles_line.dart';
import 'package:transport_app/driver/favourite_routes_screen.dart';
import 'package:transport_app/driver/recommended_loads.dart';

import 'test_utils.dart';

final now = DateTime(2026, 10, 4);

Vehicle vehicle({
  String id = 'v1',
  String type = '20ft',
  num capacity = 10,
  String availability = VehicleAvailability.available,
  String status = VehicleStatus.active,
  Map<String, VehicleDocInfo> docs = const {},
}) =>
    Vehicle(id: id, ownerId: 'd1', number: 'MH12AB1234', type: type, capacity: capacity, rcNumber: 'RC', status: status, availability: availability, docs: docs);

Load load(String id, {String pickup = 'Delhi', String drop = 'Mumbai', String type = '20ft', num weight = 8, num? budget = 25000, DateTime? created, String status = 'open'}) => Load(
      id: id, shipperId: 'c1', pickup: pickup, drop: drop, cargoType: 'FMCG', weight: weight, vehicleType: type,
      budget: budget, pickupDate: null, notes: '', status: status,
      createdAt: created == null ? null : Timestamp.fromDate(created));

DriverContext ctx({List<Vehicle>? vehicles, bool verified = true, String? anchor, bool active = false, List<FavouriteRoute> favs = const []}) =>
    DriverContext(vehicles: vehicles ?? [vehicle()], verified: verified, anchorPlace: anchor, anchorIsActiveTrip: active, favourites: favs, now: now);

void main() {
  group('LoadRanker eligibility', () {
    test('needs matching type, capacity >= weight, free active vehicle, valid papers, verified driver', () {
      expect(LoadRanker.matchFor(load('a'), ctx()), isNotNull);
      expect(LoadRanker.matchFor(load('a', type: '32ft'), ctx()), isNull);
      expect(LoadRanker.matchFor(load('a', weight: 10.5), ctx()), isNull);
      expect(LoadRanker.matchFor(load('a', weight: 10), ctx()), isNotNull);
      expect(LoadRanker.matchFor(load('a'), ctx(vehicles: [vehicle(availability: VehicleAvailability.onTrip)])), isNull);
      expect(LoadRanker.matchFor(load('a'), ctx(vehicles: [vehicle(availability: VehicleAvailability.suspended)])), isNull);
      expect(LoadRanker.matchFor(load('a'), ctx(vehicles: [vehicle(status: VehicleStatus.inactive)])), isNull);
      expect(LoadRanker.matchFor(load('a'), ctx(verified: false)), isNull);
      expect(LoadRanker.matchFor(load('a', status: 'matched'), ctx()), isNull);
      final expired = vehicle(docs: {VehicleDocKind.insurance: VehicleDocInfo(number: 'X', expiry: DateTime(2026, 9, 1))});
      expect(LoadRanker.matchFor(load('a'), ctx(vehicles: [expired])), isNull);
      final valid = vehicle(docs: {VehicleDocKind.insurance: VehicleDocInfo(number: 'X', expiry: DateTime(2027, 9, 1))});
      expect(LoadRanker.matchFor(load('a'), ctx(vehicles: [valid])), isNotNull);
    });

    test('picks the best of several vehicles', () {
      final small = vehicle(id: 'small', capacity: 8.5);
      final big = vehicle(id: 'big', capacity: 20);
      final m = LoadRanker.matchFor(load('a', weight: 8), ctx(vehicles: [big, small]))!;
      expect(m.vehicle.id, 'small'); // fuller truck scores the best-fit bonus
      expect(m.reasons, contains(MatchReason.bestFit));
    });
  });

  group('LoadRanker scoring', () {
    test('closer pickup ranks higher; ties go to the newest load', () {
      final near = load('near', pickup: 'Gurgaon, Delhi NCR', created: DateTime(2026, 10, 1));
      final far = load('far', pickup: 'Chennai', created: DateTime(2026, 10, 3));
      final r = LoadRanker.rank([far, near], ctx(anchor: 'Delhi'));
      expect(r.map((m) => m.load.id), ['near', 'far']);
      expect(r.first.reasons, contains(MatchReason.nearPickup));

      final a = load('a', created: DateTime(2026, 10, 1)), b = load('b', created: DateTime(2026, 10, 2));
      expect(LoadRanker.rank([a, b], ctx()).map((m) => m.load.id), ['b', 'a']);
    });

    test('return load: pickup near the active trip drop is boosted', () {
      final ret = load('ret', pickup: 'Pune', drop: 'Delhi');
      final other = load('other', pickup: 'Kolkata', drop: 'Delhi');
      final r = LoadRanker.rank([other, ret], ctx(anchor: 'Mumbai', active: true, vehicles: [vehicle(availability: VehicleAvailability.onTrip)]));
      expect(r.first.load.id, 'ret');
      expect(r.first.reasons, contains(MatchReason.returnLoad));
      expect(r.last.reasons, isNot(contains(MatchReason.returnLoad)));
      // Without an active trip the same busy vehicle is not eligible.
      expect(LoadRanker.rank([ret], ctx(anchor: 'Mumbai', vehicles: [vehicle(availability: VehicleAvailability.onTrip)])), isEmpty);
    });

    test('favourite routes boost matching loads (aliases and extra text allowed)', () {
      const fav = FavouriteRoute(id: 'x', pickup: 'Bombay', drop: 'Bangalore');
      final onRoute = load('fav', pickup: 'Andheri, Mumbai', drop: 'Bengaluru');
      final offRoute = load('off', pickup: 'Andheri, Mumbai', drop: 'Chennai');
      final r = LoadRanker.rank([offRoute, onRoute], ctx(favs: [fav]));
      expect(r.first.load.id, 'fav');
      expect(r.first.reasons, contains(MatchReason.favouriteRoute));
      expect(FavouriteRoute.idFor('Bombay', 'Bangalore'), FavouriteRoute.idFor('mumbai ', 'Bengaluru'));
    });
  });

  test('countMatchingVehicles and countNew', () {
    final vs = [vehicle(id: '1'), vehicle(id: '2', capacity: 5), vehicle(id: '3', type: '32ft'), vehicle(id: '4', availability: VehicleAvailability.maintenance)];
    expect(LoadRanker.countMatchingVehicles(vs, vehicleType: '20ft', weight: 8, now: now), 1);
    expect(LoadRanker.countMatchingVehicles(vs, vehicleType: '20ft', weight: 3, now: now), 2);
    final loads = [load('a', created: DateTime(2026, 10, 3)), load('b', created: DateTime(2026, 10, 1)), load('c')];
    expect(LoadRanker.countNew(loads, DateTime(2026, 10, 2)), 1);
    expect(LoadRanker.countNew(loads, null), 0);
  });

  group('with Firestore', () {
    late FakeFirebaseFirestore db;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = FakeFirebaseFirestore();
      Backend.useFakes(db: db, uid: () => 'd1');
    });

    test('favourite routes: dedupe, remove, cap at 20', () async {
      expect(await MatchService.addFavourite('Mumbai', 'Delhi'), isTrue);
      expect(await MatchService.addFavourite('Bombay', 'New Delhi'), isTrue); // same route
      expect((await MatchService.watchFavourites().first), hasLength(1));
      for (var i = 0; i < 19; i++) {
        expect(await MatchService.addFavourite('Place$i', 'Spot$i'), isTrue);
      }
      expect(await MatchService.addFavourite('Extra', 'Route'), isFalse);
      expect(await MatchService.addFavourite('Mumbai', 'Delhi'), isTrue); // existing still updates
      await MatchService.removeFavourite((await MatchService.watchFavourites().first).first.id);
      expect(await MatchService.watchFavourites().first, hasLength(19));
      expect(MatchService.addFavourite('x', 'y'), throwsArgumentError);
    });

    test('driverContext: verified flag, vehicles, anchor from trips, favourites', () async {
      await db.collection('users').doc('d1').set({'verified': true});
      await db.collection('vehicles').doc('v1').set({'ownerId': 'd1', 'number': 'MH12AB1234', 'type': '20ft', 'capacity': 10, 'status': 'active', 'rcNumber': 'R'});
      await db.collection('bookings').doc('old').set({'driverId': 'd1', 'status': 'delivered', 'drop': 'Pune', 'timeline': {'delivered': Timestamp.fromDate(DateTime(2026, 9, 1))}});
      var c = await MatchService.driverContext(now: now);
      expect((c.verified, c.vehicles.length, c.anchorPlace, c.anchorIsActiveTrip), (true, 1, 'Pune', false));
      await db.collection('bookings').doc('act').set({'driverId': 'd1', 'status': 'in_transit', 'drop': 'Delhi'});
      c = await MatchService.driverContext(now: now);
      expect((c.anchorPlace, c.anchorIsActiveTrip), ('Delhi', true));
    });

    test('customer vehicle count and the new-loads marker', () async {
      Future<void> add(String id, Map<String, Object?> extra) => db.collection('vehicles').doc(id).set({
            'ownerId': 'x$id', 'number': 'N$id', 'type': '20ft', 'capacity': 10, 'status': 'active', 'rcNumber': 'R', ...extra});
      await add('1', {});
      await add('2', {'capacity': 4});
      await add('3', {'availability': 'on_trip'});
      await add('4', {'status': 'inactive'});
      expect(await MatchService.countMatchingVehicles(vehicleType: '20ft', weight: 8), 1);
      expect(await MatchService.countMatchingVehicles(vehicleType: '20ft', weight: 3), 2);

      expect(await MatchService.lastSeenLoads(), isNull);
      await MatchService.markLoadsSeen(DateTime(2026, 10, 4, 10));
      expect(await MatchService.lastSeenLoads(), DateTime(2026, 10, 4, 10));
    });

    testWidgets('matching vehicles line updates with the weight', (tester) async {
      await db.collection('vehicles').doc('1').set({'ownerId': 'x', 'number': 'N1', 'type': '20ft', 'capacity': 10, 'status': 'active', 'rcNumber': 'R'});
      Widget app(num? w) => MaterialApp(home: Scaffold(body: MatchingVehiclesLine(vehicleType: '20ft', weight: w)));
      await tester.pumpWidget(app(null));
      await settle(tester);
      expect(find.byKey(const ValueKey('matchingVehicles')), findsNothing);
      await tester.pumpWidget(app(8));
      await settle(tester);
      expect(find.text('1 matching vehicles available'), findsOneWidget);
      await tester.pumpWidget(app(50));
      await settle(tester);
      expect(find.textContaining('No matching vehicles'), findsOneWidget);
    });

    testWidgets('favourite routes screen adds and removes a route', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: FavouriteRoutesScreen()));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('favPickup')), 'Mumbai');
      await tester.enterText(find.byKey(const ValueKey('favDrop')), 'Delhi');
      await tester.tap(find.byKey(const ValueKey('favAdd')));
      await settle(tester);
      expect(find.text('Mumbai → Delhi'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('favDelete_${'mumbai__delhi'}')));
      await settle(tester);
      expect(find.text('Mumbai → Delhi'), findsNothing);
    });

    testWidgets('recommended loads shows ranked cards with reasons; hidden when unverified', (tester) async {
      await db.collection('users').doc('d1').set({'verified': true});
      await db.collection('vehicles').doc('v1').set({'ownerId': 'd1', 'number': 'MH12AB1234', 'type': '20ft', 'capacity': 10, 'status': 'active', 'rcNumber': 'R'});
      await MatchService.addFavourite('Delhi', 'Mumbai');
      Widget app() => MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RecommendedLoads(
                  loads: [load('a'), load('b', type: '32ft')],
                  cardBuilder: (m) => Column(children: [MatchReasonChips(reasons: m.reasons), Text('card ${m.load.id}')]),
                ),
              ),
            ),
          );
      await tester.pumpWidget(app());
      await settle(tester);
      expect(find.text('card a'), findsOneWidget);
      expect(find.text('card b'), findsNothing);
      expect(find.text('Favourite route'), findsOneWidget);

      await db.collection('users').doc('d1').set({'verified': false});
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      await settle(tester);
      expect(find.text('card a'), findsNothing);
    });
  });
}
