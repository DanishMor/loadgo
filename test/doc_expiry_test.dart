import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/documents/doc_expiry.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/services/admin_console_service.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/doc_expiry_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/driver/doc_suspension_banner.dart';

import 'test_utils.dart';

Timestamp ago(int days) => Timestamp.fromDate(DateTime.now().subtract(Duration(days: days)));
Timestamp ahead(int days) => Timestamp.fromDate(DateTime.now().add(Duration(days: days)));

Vehicle vehicle({String availability = 'available', Map<String, Object?> docs = const {}, DateTime? override}) => Vehicle(
      id: 'v1', ownerId: 'o', number: 'MH12AB1234', type: '20ft', capacity: 10, rcNumber: 'RC', status: 'active', availability: availability,
      docs: {for (final e in docs.entries) e.key: VehicleDocInfo(number: 'n', expiry: (e.value as Timestamp).toDate())},
      docOverrideUntil: override,
    );

void main() {
  final now = DateTime.now();

  test('only insurance, permit and fitness block; PUC only warns; today is still valid', () {
    expect(vehicle(docs: {'insurance': ago(3)}).papersBlocked(now), isTrue);
    expect(vehicle(docs: {'permit': ago(3)}).blockingExpired(now), ['permit']);
    expect(vehicle(docs: {'puc': ago(30)}).papersBlocked(now), isFalse);
    expect(vehicle(docs: {'fitness': Timestamp.fromDate(DateTime(now.year, now.month, now.day))}).papersBlocked(now), isFalse);
    expect(vehicle(docs: {'insurance': ago(3)}, override: now.add(const Duration(days: 2))).papersBlocked(now), isFalse);
    expect(vehicle(docs: {'insurance': ago(3)}, override: now.subtract(const Duration(days: 1))).papersBlocked(now), isTrue);
  });

  test('vehicle target: suspend a free vehicle, lift only the doc suspension, never touch a trip', () {
    final expired = {'insurance': ago(3)};
    expect(DocExpiry.vehicleTarget(vehicle(docs: expired), now), 'doc_expired');
    expect(DocExpiry.vehicleTarget(vehicle(availability: 'on_trip', docs: expired), now), isNull);
    expect(DocExpiry.vehicleTarget(vehicle(availability: 'maintenance', docs: expired), now), isNull);
    expect(DocExpiry.vehicleTarget(vehicle(availability: 'suspended', docs: expired), now), isNull);
    expect(DocExpiry.vehicleTarget(vehicle(availability: 'doc_expired', docs: expired), now), isNull);
    expect(DocExpiry.vehicleTarget(vehicle(availability: 'doc_expired', docs: {'insurance': ahead(100)}), now), 'available');
    expect(DocExpiry.vehicleTarget(vehicle(availability: 'doc_expired', docs: expired, override: now.add(const Duration(days: 1))), now), 'available');
    expect(DocExpiry.vehicleTarget(vehicle(availability: 'suspended', docs: {'insurance': ahead(100)}), now), isNull);
  });

  test('licence: expired blocks unless an admin override is active', () {
    Map<String, dynamic> p(Timestamp exp, {Timestamp? override}) => {'driverKyc': {'dlExpiry': exp}, 'docOverrideUntil': ?override};
    expect(DocExpiry.licenceBlocked(p(ago(2)), now), isTrue);
    expect(DocExpiry.licenceBlocked(p(ahead(2)), now), isFalse);
    expect(DocExpiry.licenceBlocked(p(ago(2), override: ahead(3)), now), isFalse);
    expect(DocExpiry.licenceBlocked(p(ago(2), override: ago(1)), now), isTrue);
    expect(DocExpiry.licenceBlocked(null, now), isFalse);
    expect(DocExpiry.licenceBlocked(const {}, now), isFalse);
  });

  group('with Firestore', () {
    late FakeFirebaseFirestore db;
    String? uid;

    setUp(() {
      db = FakeFirebaseFirestore();
      Backend.useFakes(db: db, uid: () => uid);
    });

    Future<String> addVehicle() async {
      uid = 'driver1';
      return VehicleService.add(number: 'MH12AB1000', type: '20ft', capacity: 10, rcNumber: 'RC1');
    }

    test('saving expired papers suspends the vehicle; renewing lifts it; admin override works', () async {
      final id = await addVehicle();
      await VehicleService.saveDocuments(id, {'insurance': VehicleDocInfo(number: 'P1', expiry: ago(2).toDate())});
      expect((await db.collection('vehicles').doc(id).get())['availability'], 'doc_expired');
      await VehicleService.saveDocuments(id, {'insurance': VehicleDocInfo(number: 'P1', expiry: ahead(200).toDate())});
      expect((await db.collection('vehicles').doc(id).get())['availability'], 'available');

      await db.collection('vehicles').doc(id).update({'docs.permit': {'number': 'X', 'expiry': ago(5)}});
      expect(await DocExpiryService.syncMine(), 1);
      expect((await db.collection('vehicles').doc(id).get())['availability'], 'doc_expired');
      expect(await DocExpiryService.syncMine(), 0);
      uid = 'admin1';
      await AdminConsoleService.overrideVehicleDocs(id);
      uid = 'driver1';
      expect((await db.collection('vehicles').doc(id).get())['availability'], 'available');
      expect(await DocExpiryService.syncMine(), 0);
    });

    test('a driver with an expired licence, or an expired vehicle paper, cannot accept; override lifts it', () async {
      uid = 'customer1';
      final loadId = await LoadService.post(
          pickup: 'Delhi', drop: 'Mumbai', cargoType: 'FMCG', weight: 8, vehicleType: '20ft', budget: 25000,
          pickupDate: DateTime(2026, 10, 5), notes: '');
      final vid = await addVehicle();
      final vehicle = (await VehicleService.fetchMyActive()).firstWhere((v) => v.id == vid);

      await db.collection('users').doc('driver1').set({'driverKyc': {'dlExpiry': ago(3)}});
      await expectLater(BookingService.accept(loadId: loadId, vehicle: vehicle), throwsA(isA<DocsExpiredException>().having((e) => e.what, 'w', 'licence')));
      uid = 'admin1';
      await AdminConsoleService.overrideLicence('driver1');
      uid = 'driver1';

      await db.collection('vehicles').doc(vid).update({'docs.insurance': {'number': 'P', 'expiry': ago(1)}});
      final stale = (await VehicleService.fetchMyActive()).firstWhere((v) => v.id == vid);
      await expectLater(BookingService.accept(loadId: loadId, vehicle: stale), throwsA(isA<DocsExpiredException>().having((e) => e.what, 'w', 'vehicle')));
      uid = 'admin1';
      await AdminConsoleService.overrideVehicleDocs(vid);
      uid = 'driver1';
      final ok = (await VehicleService.fetchMyActive()).firstWhere((v) => v.id == vid);
      expect(await BookingService.accept(loadId: loadId, vehicle: ok), isNotEmpty);
    });

    testWidgets('banner names the expired licence and the held vehicle', (tester) async {
      final id = await tester.runAsync(addVehicle);
      await tester.runAsync(() => db.collection('vehicles').doc(id).update({'docs.insurance': {'number': 'P', 'expiry': ago(1)}}));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DocSuspensionBanner(
            vehicles: VehicleService.watchMine(),
            profile: {'driverKyc': {'dlExpiry': ago(4)}},
            onOpenVehicles: () {},
            onOpenLicence: () {},
          ),
        ),
      ));
      await settle(tester);
      expect(find.byKey(const ValueKey('licenceBanner')), findsOneWidget);
      expect(find.byKey(ValueKey('heldVehicle_$id')), findsOneWidget);
      expect(find.textContaining('MH12AB1000'), findsOneWidget);
    });
  });
}
