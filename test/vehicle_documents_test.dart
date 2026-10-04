import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/core/widgets/common.dart';
import 'package:transport_app/driver/vehicle_alerts_banner.dart';
import 'package:transport_app/driver/vehicle_documents_screen.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  String? uid;

  setUp(() {
    db = FakeFirebaseFirestore();
    uid = 'driver1';
    Backend.useFakes(db: db, uid: () => uid);
  });

  Future<Vehicle> vehicle(String id) async => Vehicle.fromDoc(await db.collection('vehicles').doc(id).get());

  group('Vehicle model', () {
    final now = DateTime(2026, 10, 4);
    final v = Vehicle(
      id: 'v', ownerId: 'd', number: 'X', type: 'Mini', capacity: 1, rcNumber: 'R', status: 'active',
      docs: {
        'insurance': VehicleDocInfo(number: 'P1', expiry: DateTime(2026, 10, 20)),
        'puc': VehicleDocInfo(expiry: DateTime(2026, 9, 1)),
        'fitness': VehicleDocInfo(expiry: DateTime(2027, 6, 1)),
      },
      nextServiceDate: DateTime(2026, 10, 8),
    );

    test('expiring within 30 days includes expired papers', () {
      expect(v.docsExpiringWithin(now), ['insurance', 'puc']);
      expect(v.expiredDocs(now), ['puc']);
      expect(v.serviceDue(now), isTrue);
      expect(v.serviceDue(DateTime(2026, 9, 1)), isFalse);
    });

    test('alerts sum across vehicles', () {
      final a = vehicleAlerts([v, v], now);
      expect(a.expiringDocs, 4);
      expect(a.serviceDue, 2);
    });

    test('old documents default to available with no papers', () async {
      await db.collection('vehicles').doc('old').set({'ownerId': 'd', 'number': 'MH12AB1234', 'type': 'Mini', 'capacity': 1, 'status': 'active'});
      final old = await vehicle('old');
      expect(old.availability, VehicleAvailability.available);
      expect(old.docs, isEmpty);
      expect(old.canTakeBooking, isTrue);
    });
  });

  group('duplicate numbers', () {
    test('a number already registered by another account is refused', () async {
      await VehicleService.add(number: 'MH12 AB 1234', type: 'Mini', capacity: 1, rcNumber: 'RC1');
      expect((await db.collection('vehicle_numbers').doc('MH12AB1234').get()).data()!['ownerId'], 'driver1');
      uid = 'driver2';
      await expectLater(
        VehicleService.add(number: 'mh12ab1234', type: 'Mini', capacity: 1, rcNumber: 'RC2'),
        throwsA(isA<DuplicateVehicleException>()),
      );
      expect((await db.collection('vehicles').get()).docs, hasLength(1));
    });

    test('renumbering moves the reservation and frees the old number', () async {
      final id = await VehicleService.add(number: 'MH12AB1234', type: 'Mini', capacity: 1, rcNumber: 'RC1');
      await VehicleService.update(vehicleId: id, number: 'DL01ZZ0001', type: 'Mini', capacity: 1, rcNumber: 'RC1');
      expect((await db.collection('vehicle_numbers').doc('MH12AB1234').get()).exists, isFalse);
      expect((await db.collection('vehicle_numbers').doc('DL01ZZ0001').get()).data()!['vehicleId'], id);
      // Saving without changing the number is fine.
      await VehicleService.update(vehicleId: id, number: 'DL01ZZ0001', type: 'Mini', capacity: 2, rcNumber: 'RC1');
      uid = 'driver2';
      await VehicleService.add(number: 'MH12AB1234', type: 'Mini', capacity: 1, rcNumber: 'RC2');
    });
  });

  group('availability follows bookings', () {
    Future<(String, Vehicle)> book() async {
      uid = 'customer1';
      final loadId = await LoadService.post(
          pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 1, vehicleType: 'Mini', budget: 5000,
          pickupDate: DateTime(2026, 10, 5), notes: '');
      uid = 'driver1';
      final vid = await VehicleService.add(number: 'MH12AB1234', type: 'Mini', capacity: 2, rcNumber: 'RC1');
      final v = await vehicle(vid);
      return (await BookingService.accept(loadId: loadId, vehicle: v), v);
    }

    test('accept -> on_trip; delivered -> available', () async {
      final (bookingId, v) = await book();
      expect((await vehicle(v.id)).availability, VehicleAvailability.onTrip);
      for (var i = 0; i < 3; i++) {
        await BookingService.advance(bookingId);
      }
      expect((await vehicle(v.id)).availability, VehicleAvailability.available);
    });

    test('driver cancel frees the vehicle', () async {
      final (bookingId, v) = await book();
      await BookingService.cancelByDriver(bookingId);
      expect((await vehicle(v.id)).availability, VehicleAvailability.available);
    });

    test('a busy vehicle cannot accept another load', () async {
      final (_, v) = await book();
      uid = 'customer1';
      final second = await LoadService.post(
          pickup: 'Pune', drop: 'Goa', cargoType: 'FMCG', weight: 1, vehicleType: 'Mini', budget: 5000,
          pickupDate: DateTime(2026, 10, 6), notes: '');
      uid = 'driver1';
      await expectLater(BookingService.accept(loadId: second, vehicle: await vehicle(v.id)), throwsA(isA<VehicleBusyException>()));

      await db.collection('vehicles').doc(v.id).update({'availability': VehicleAvailability.maintenance});
      expect((await vehicle(v.id)).canTakeBooking, isFalse);
    });

    test('setAvailability only accepts the owner-managed values', () async {
      final id = await VehicleService.add(number: 'MH12AB1234', type: 'Mini', capacity: 1, rcNumber: 'RC1');
      await VehicleService.setAvailability(id, VehicleAvailability.maintenance);
      expect((await vehicle(id)).availability, VehicleAvailability.maintenance);
      expect(() => VehicleService.setAvailability(id, VehicleAvailability.suspended), throwsArgumentError);
    });
  });

  testWidgets('documents screen saves numbers, dates and maintenance', (tester) async {
    final id = await VehicleService.add(number: 'MH12AB1234', type: 'Mini', capacity: 1, rcNumber: 'RC1');
    await db.collection('vehicles').doc(id).update({
      'docs': {'puc': {'number': 'OLD', 'expiry': Timestamp.fromDate(DateTime(2020, 1, 1))}},
    });
    final v = await vehicle(id);
    languageNotifier.value = AppLanguage.english;
    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(home: VehicleDocumentsScreen(vehicle: v)),
    ));
    expect(find.text('Unverified'), findsWidgets);
    expect(find.text('Expired'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('docNumber_insurance')), 'pol-77');
    // A focused field keeps scrolling itself back into view; release it.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('maintenanceSwitch')));
    await tester.tap(find.byKey(const ValueKey('maintenanceSwitch')));
    await tester.pump();
    await tester.ensureVisible(find.byType(PrimaryButton));
    await tester.tap(find.byType(PrimaryButton));
    await settle(tester);
    final saved = (await tester.runAsync(() => vehicle(id)))!;
    expect(saved.docs['insurance']!.number, 'pol-77', reason: 'stored as typed (keyboard capitalises on devices)');
    expect(saved.docs['puc']!.number, 'OLD');
    expect(saved.docs.containsKey('permit'), isFalse, reason: 'empty papers are not stored');
    expect(saved.availability, VehicleAvailability.maintenance);
  });

  testWidgets('home banner counts expiring papers and hides when clear', (tester) async {
    final soon = DateTime.now().add(const Duration(days: 5));
    final v = Vehicle(
      id: 'v', ownerId: 'd', number: 'X', type: 'Mini', capacity: 1, rcNumber: 'R', status: 'active',
      docs: {'insurance': VehicleDocInfo(expiry: soon), 'permit': VehicleDocInfo(expiry: soon)},
    );
    var taps = 0;
    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(home: Scaffold(body: VehicleAlertsBanner(vehicles: Stream.value([v]), onTap: () => taps++))),
    ));
    await tester.pump();
    expect(find.text('2 vehicle document(s) expire within 30 days'), findsOneWidget);
    await tester.tap(find.byType(VehicleAlertsBanner));
    expect(taps, 1);

    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(home: Scaffold(body: VehicleAlertsBanner(key: UniqueKey(), vehicles: Stream.value(const []), onTap: _noop))),
    ));
    await tester.pump();
    expect(find.byIcon(Icons.assignment_late_rounded), findsNothing);
  });
}

void _noop() {}
