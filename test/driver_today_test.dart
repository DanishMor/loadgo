import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/matching/load_ranker.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/driver/driver_today.dart';

import 'test_utils.dart';

/// MASTER-6 Task 22: the driver's day on one strip.
void main() {
  final now = DateTime(2026, 10, 9, 12);

  Booking trip(String id, String status, {DateTime? scheduledAt, num fare = 0, DateTime? delivered}) => Booking(
        id: id, loadId: id, driverId: 'd1', vehicleId: 'v1', customerId: 'c', status: status, pickup: 'Delhi', drop: 'Jaipur', cargoType: 'x', weight: 1,
        vehicleType: '20ft', budget: fare, pickupDate: null, notes: '', vehicleNumber: 'MH12AB1', driverName: 'D', driverPhone: '1',
        timeline: {'delivered': ?delivered}, scheduledAt: scheduledAt,
      );

  Vehicle vehicle({Map<String, VehicleDocInfo> docs = const {}}) => Vehicle(id: 'v1', ownerId: 'd1', number: 'MH12AB1234', type: '20ft', capacity: 10, rcNumber: 'RC', status: VehicleStatus.active, availability: VehicleAvailability.available, docs: docs);

  Load load(String id, {String type = '20ft'}) => Load(id: id, shipperId: 'c1', pickup: 'Delhi', drop: 'Mumbai', cargoType: 'FMCG', weight: 8, vehicleType: type, budget: 25000, pickupDate: null, notes: '', status: 'open');

  test('papers: only those running out within 14 days (expired ones included), not later ones', () {
    final v = vehicle(docs: {
      VehicleDocKind.insurance: VehicleDocInfo(number: 'I', expiry: now.add(const Duration(days: 10))),
      VehicleDocKind.permit: VehicleDocInfo(number: 'P', expiry: now.add(const Duration(days: 40))),
      VehicleDocKind.fitness: VehicleDocInfo(number: 'F', expiry: now.subtract(const Duration(days: 2))),
    });
    final t = DriverToday.compute(bookings: const [], vehicles: [v], loads: const [], ctx: null, now: now);
    expect(t.papersExpiring, 2);
  });

  test('trips: running ones and scheduled ones are counted apart; delivered and cancelled are not', () {
    final t = DriverToday.compute(
      bookings: [
        trip('a', 'in_transit'),
        trip('b', 'accepted', scheduledAt: now.add(const Duration(days: 2))),
        trip('c', 'delivered', delivered: now),
        trip('d', 'cancelled'),
      ],
      vehicles: const [],
      loads: const [],
      ctx: null,
      now: now,
    );
    expect((t.activeTrips, t.upcomingCount), (1, 1));
  });

  test('recommended loads come from the ranker; none without a context; none for an unverified driver', () {
    DriverContext ctx({bool verified = true}) => DriverContext(vehicles: [vehicle()], verified: verified, now: now);
    final loads = [load('a'), load('b'), load('c', type: '32ft')];
    expect(DriverToday.compute(bookings: const [], vehicles: [vehicle()], loads: loads, ctx: ctx(), now: now).recommendedLoads, 2);
    expect(DriverToday.compute(bookings: const [], vehicles: [vehicle()], loads: loads, ctx: null, now: now).recommendedLoads, 0);
    expect(DriverToday.compute(bookings: const [], vehicles: [vehicle()], loads: loads, ctx: ctx(verified: false), now: now).recommendedLoads, 0);
  });

  test('earnings today count only trips delivered today', () {
    final t = DriverToday.compute(
      bookings: [trip('a', 'delivered', fare: 5000, delivered: now), trip('b', 'delivered', fare: 9000, delivered: now.subtract(const Duration(days: 3)))],
      vehicles: const [],
      loads: const [],
      ctx: null,
      now: now,
    );
    expect(t.earningsToday, 5000);
    final both = DriverToday.compute(bookings: [trip('b', 'delivered', fare: 9000, delivered: now.subtract(const Duration(days: 3)))], vehicles: const [], loads: const [], ctx: null, now: now);
    expect(both.earningsToday, 0);
  });

  testWidgets('the strip shows the four numbers and each tile opens its screen', (tester) async {
    final b = StreamController<List<Booking>>();
    final v = StreamController<List<Vehicle>>();
    final l = StreamController<List<Load>>();
    addTearDown(() {
      b.close();
      v.close();
      l.close();
    });
    final hits = <String>[];
    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(
        home: Scaffold(
          body: DriverTodayStrip(
            bookings: b.stream,
            vehicles: v.stream,
            loads: l.stream,
            now: () => now,
            loadContext: () async => DriverContext(vehicles: [vehicle()], now: now),
            onEarnings: () => hits.add('earnings'),
            onTrips: () => hits.add('trips'),
            onPapers: () => hits.add('papers'),
            onLoads: () => hits.add('loads'),
          ),
        ),
      ),
    ));
    await settle(tester);
    b.add([trip('a', 'in_transit'), trip('b', 'accepted', scheduledAt: now.add(const Duration(days: 2)))]);
    v.add([vehicle(docs: {VehicleDocKind.insurance: VehicleDocInfo(number: 'I', expiry: now.add(const Duration(days: 3)))})]);
    l.add([load('x'), load('y')]);
    await settle(tester);
    String n(String id) => tester.widget<Text>(find.byKey(ValueKey('todayN_$id'))).data!;
    expect((n('trips'), n('papers'), n('loads')), ('2', '1', '2'));
    expect(find.text('Trips: 1 on now, 1 coming'), findsOneWidget);
    for (final id in ['earnings', 'trips', 'papers', 'loads']) {
      await tester.tap(find.byKey(ValueKey('today_$id')));
    }
    expect(hits, ['earnings', 'trips', 'papers', 'loads']);
  });
}
