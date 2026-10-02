import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/vehicle_service.dart';

void main() {
  late FakeFirebaseFirestore db;
  String? uid = 'driver1';

  setUp(() {
    db = FakeFirebaseFirestore();
    uid = 'driver1';
    Backend.useFakes(db: db, uid: () => uid);
  });

  test('normalizes and validates vehicle numbers', () {
    expect(VehicleService.normalizeNumber('mh 12-ab 1234'), 'MH12AB1234');
    expect(VehicleService.isValidNumber('MH12AB1234'), isTrue);
    expect(VehicleService.isValidNumber('ab'), isFalse);
    expect(VehicleService.isValidNumber('MH12@1234'), isFalse);
  });

  test('add stores the vehicle with owner, active status and timestamp', () async {
    final id = await VehicleService.add(number: 'mh12 ab 1234', type: '14ft', capacity: 9, rcNumber: 'rc123');
    final doc = await db.collection('vehicles').doc(id).get();
    expect(doc.data(), containsPair('ownerId', 'driver1'));
    expect(doc['number'], 'MH12AB1234');
    expect(doc['type'], '14ft');
    expect(doc['capacity'], 9);
    expect(doc['rcNumber'], 'RC123');
    expect(doc['status'], VehicleStatus.active);
    expect(doc['createdAt'], isNotNull);
  });

  test('watchMine only returns the signed-in owner vehicles', () async {
    await VehicleService.add(number: 'MH12AB1234', type: 'Mini', capacity: 1, rcNumber: 'RC1');
    uid = 'driver2';
    await VehicleService.add(number: 'KA01CD5678', type: 'Trailer', capacity: 30, rcNumber: 'RC2');

    final mine = await VehicleService.watchMine().first;
    expect(mine.map((v) => v.number), ['KA01CD5678']);
  });

  test('setActive toggles status and fetchMyActive filters inactive', () async {
    final id = await VehicleService.add(number: 'MH12AB1234', type: 'Mini', capacity: 1, rcNumber: 'RC1');
    expect(await VehicleService.fetchMyActive(), hasLength(1));

    await VehicleService.setActive(id, false);
    expect((await db.collection('vehicles').doc(id).get())['status'], VehicleStatus.inactive);
    expect(await VehicleService.fetchMyActive(), isEmpty);
  });

  test('watchMine is empty when signed out', () async {
    uid = null;
    expect(await VehicleService.watchMine().first, isEmpty);
  });

  rcUploadTests();
}

void rcUploadTests() {
  group('RC upload', () {
    late FakeFirebaseFirestore db;
    final uploads = <String, Uint8List>{};

    setUp(() {
      db = FakeFirebaseFirestore();
      uploads.clear();
      Backend.useFakes(
        db: db,
        uid: () => 'driver1',
        uploader: (path, bytes, type) async {
          uploads[path] = bytes;
          return 'https://firebasestorage.googleapis.com/fake/$path';
        },
      );
    });

    test('add uploads the RC under the owner path and saves rcImageUrl', () async {
      final id = await VehicleService.add(
          number: 'MH12AB1234', type: 'Mini', capacity: 1, rcNumber: 'RC1', rcImage: Uint8List.fromList([1, 2, 3]));
      expect(uploads.keys, ['vehicles/driver1/$id/rc.jpg']);
      final doc = await db.collection('vehicles').doc(id).get();
      expect(doc['rcImageUrl'], 'https://firebasestorage.googleapis.com/fake/vehicles/driver1/$id/rc.jpg');
    });

    test('add without RC leaves rcImageUrl absent; update can add it later', () async {
      final id = await VehicleService.add(number: 'MH12AB1234', type: 'Mini', capacity: 1, rcNumber: 'RC1');
      expect((await db.collection('vehicles').doc(id).get()).data()!.containsKey('rcImageUrl'), isFalse);

      await VehicleService.update(
          vehicleId: id, number: 'mh12ab9999', type: '14ft', capacity: 7, rcNumber: 'rc2', rcImage: Uint8List(4));
      final d = (await db.collection('vehicles').doc(id).get()).data()!;
      expect(d['number'], 'MH12AB9999');
      expect(d['type'], '14ft');
      expect(d['rcImageUrl'], isNotNull);
      expect(d['status'], VehicleStatus.active, reason: 'edit keeps status');
    });

    test('update without a new image keeps the existing rcImageUrl', () async {
      final id = await VehicleService.add(
          number: 'MH12AB1234', type: 'Mini', capacity: 1, rcNumber: 'RC1', rcImage: Uint8List(1));
      final before = (await db.collection('vehicles').doc(id).get())['rcImageUrl'];
      await VehicleService.update(vehicleId: id, number: 'MH12AB1234', type: 'Mini', capacity: 2, rcNumber: 'RC1');
      expect((await db.collection('vehicles').doc(id).get())['rcImageUrl'], before);
    });
  });
}
