import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/fleet/transporter_board.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/fleet.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/transporter/transporter_logic.dart';
import 'package:transport_app/fleet/transporter_board_card.dart';


/// MASTER-6 Task 28: the transporter's board.
void main() {
  final now = DateTime(2026, 10, 9, 12);

  Booking trip(String id, String status, {String vehicle = 'v1', String driver = 'd1', DateTime? at}) => Booking(
        id: id, loadId: id, driverId: driver, vehicleId: vehicle, customerId: 'c', status: status, pickup: 'A', drop: 'B', cargoType: 'x', weight: 1,
        vehicleType: '20ft', budget: 1000, pickupDate: null, notes: '', vehicleNumber: 'X', driverName: 'D', driverPhone: '1',
        timeline: {'accepted': at ?? now.subtract(const Duration(days: 2)), if (status == 'delivered' || status == 'cancelled') status: at ?? now.subtract(const Duration(days: 1)), if (status == 'picked_up' || status == 'in_transit') 'picked_up': now.subtract(const Duration(days: 1))},
      );

  Vehicle veh(String id) => Vehicle(id: id, ownerId: 'o1', number: 'MH12AB$id', type: '20ft', capacity: 10, rcNumber: 'R', status: 'active', availability: 'available');

  const members = [
    FleetMember(id: 'o1_d1', ownerId: 'o1', ownerName: 'O', driverId: 'd1', driverName: 'Ramesh', driverPhone: '+91', active: true),
  ];

  test('trips by status: running ones all, finished ones only from the last 30 days', () {
    final b = TransporterBoard.compute(
      vehicles: [veh('v1')],
      bookings: [
        trip('a', 'in_transit'),
        trip('b', 'in_transit'),
        trip('c', 'loading'),
        trip('d', 'delivered'),
        trip('e', 'delivered', at: now.subtract(const Duration(days: 45))),
        trip('f', 'cancelled'),
      ],
      members: members,
      accounts: const [],
      now: now,
    );
    expect(b.tripsByStatus['in_transit'], 2);
    expect(b.tripsByStatus['loading'], 1);
    expect(b.tripsByStatus['delivered'], 1);
    expect(b.tripsByStatus['cancelled'], 1);
    expect(b.tripsByStatus['accepted'], 0);
  });

  test('use, drivers and parties: least used first, drivers by name then trips, only parties that owe', () {
    final b = TransporterBoard.compute(
      vehicles: [veh('v1'), veh('v2')],
      bookings: [trip('a', 'delivered', vehicle: 'v1'), trip('b', 'delivered', vehicle: 'v1'), trip('c', 'delivered', vehicle: 'v1', driver: 'd9')],
      members: members,
      accounts: const [
        TripAccount(bookingId: 'a', partyId: 'p1', partyName: 'Acme', revenuePaise: 500000, receivedPaise: 100000),
        TripAccount(bookingId: 'b', partyId: 'p2', partyName: 'Zeta', revenuePaise: 300000, receivedPaise: 300000),
        TripAccount(bookingId: 'c', partyId: 'p3', partyName: 'Beta', revenuePaise: 900000, receivedPaise: 0),
      ],
      now: now,
    );
    expect(b.leastUsed.first.vehicle.id, 'v2'); // never on the road
    expect(b.leastUsed.first.daysOnRoad, 0);
    expect(b.utilisation, greaterThan(0));
    expect(b.drivers.first.trips, 2);
    expect(b.drivers.first.driver, 'Ramesh');
    expect(b.drivers.last.driver, 'd9'); // no name known: the id
    expect(b.parties.map((p) => p.partyName), ['Beta', 'Acme']); // Zeta paid in full
    expect(b.totalDuePaise, 900000 + 400000);
  });

  test('an empty fleet gives an empty board without errors', () {
    final b = TransporterBoard.compute(vehicles: const [], bookings: const [], members: const [], accounts: const [], now: now);
    expect(b.tripsByStatus.values.every((v) => v == 0), isTrue);
    expect(b.utilisation, 0.0);
    expect(b.leastUsed, isEmpty);
    expect(b.drivers, isEmpty);
    expect(b.parties, isEmpty);
    expect(b.totalDuePaise, 0);
  });

  testWidgets('the card shows status chips, use, drivers and the parties that owe; and says so when nobody owes', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget card(List<TripAccount> accounts, List<Booking> bookings) => LanguageScope(
          notifier: languageNotifier,
          child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: TransporterBoardCard(vehicles: [veh('v1')], bookings: bookings, members: members, accounts: accounts, now: now)))),
        );
    await tester.pumpWidget(card(const [TripAccount(bookingId: 'a', partyId: 'p1', partyName: 'Acme', revenuePaise: 500000, receivedPaise: 100000)], [trip('a', 'in_transit'), trip('b', 'delivered')]));
    expect(find.byKey(const ValueKey('tbStatus_in_transit')), findsOneWidget);
    expect(find.byKey(const ValueKey('tbStatus_delivered')), findsOneWidget);
    expect(find.byKey(const ValueKey('tbStatus_cancelled')), findsNothing);
    expect(find.byKey(const ValueKey('tbParty_p1')), findsOneWidget);
    expect(find.textContaining('Total still to receive: ₹'), findsOneWidget);
    expect(find.byKey(const ValueKey('tbUtilisation')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(card(const [], const []));
    expect(find.byKey(const ValueKey('tbNoTrips')), findsOneWidget);
    expect(find.byKey(const ValueKey('tbNoDue')), findsOneWidget);
  });
}
