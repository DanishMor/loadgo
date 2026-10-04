import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/location/geohash.dart';
import 'package:transport_app/core/matching/nearest.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/paged.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/driver/available_loads_view.dart';

import 'test_utils.dart';

const delhi = (lat: 28.6139, lng: 77.2090);

Future<void> seedLoad(FakeFirebaseFirestore db, String id, String pickup, {bool geohash = true, String status = 'open', String shipper = 'c1'}) {
  return db.collection('loads').doc(id).set({
    'shipperId': shipper,
    'pickup': pickup,
    'drop': 'Kolkata',
    'cargoType': 'FMCG',
    'weight': 5,
    'vehicleType': '20ft',
    'budget': 20000,
    'pickupDate': Timestamp.fromDate(DateTime(2026, 10, 5)),
    'status': status,
    if (geohash && pickupGeohashFor(pickup) != null) 'pickupGeohash': pickupGeohashFor(pickup),
  });
}

void main() {
  late FakeFirebaseFirestore db;
  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'driver1');
  });

  test('cells: the point sits in its own cell and neighbours wrap safely', () {
    final cells = geohashCells(delhi.lat, delhi.lng, 3);
    expect(cells, contains(geohashEncode(delhi.lat, delhi.lng, precision: 3)));
    expect(cells.length, inInclusiveRange(4, 9));
    expect(cells.every((c) => c.length == 3), isTrue);
    expect(geohashCells(89.9, 179.9, 3), isNotEmpty);
    expect(geohashCellSize(3).lat, closeTo(1.40625, 1e-9));
    expect(geohashPrecisionForKm(2), 5);
    expect(geohashPrecisionForKm(30), 4);
    expect(geohashPrecisionForKm(150), 3);
  });

  test('pickupGeohashFor uses the city table, 7 characters, null for unknown places', () {
    expect(pickupGeohashFor('Connaught Place, New Delhi')!.length, 7);
    expect(pickupGeohashFor('Delhi'), pickupGeohashFor('new delhi'));
    expect(pickupGeohashFor('Some village'), isNull);
  });

  test('posting a load stores pickupGeohash', () async {
    final id = await LoadService.post(
      pickup: 'Jaipur', drop: 'Delhi', cargoType: 'FMCG', weight: 5, vehicleType: '20ft', budget: 1000,
      pickupDate: DateTime(2026, 10, 5), notes: '',
    );
    expect((await db.collection('loads').doc(id).get()).data()!['pickupGeohash'], pickupGeohashFor('Jaipur'));
    final id2 = await LoadService.post(
      pickup: 'Some village', drop: 'Delhi', cargoType: 'FMCG', weight: 5, vehicleType: '20ft', budget: 1000,
      pickupDate: DateTime(2026, 10, 5), notes: '',
    );
    expect((await db.collection('loads').doc(id2).get()).data()!.containsKey('pickupGeohash'), isFalse);
  });

  test('watchNearby finds open loads around the driver only', () async {
    await seedLoad(db, 'delhi', 'Delhi');
    await seedLoad(db, 'faridabad', 'Faridabad');
    await seedLoad(db, 'mumbai', 'Mumbai');
    await seedLoad(db, 'chennai', 'Chennai');
    await seedLoad(db, 'matched', 'Delhi', status: 'matched');
    await seedLoad(db, 'own', 'Delhi', shipper: 'driver1');
    await seedLoad(db, 'nohash', 'Delhi', geohash: false);

    final loads = await LoadService.watchNearby(delhi).firstWhere((l) => l.isNotEmpty);
    final ids = loads.map((l) => l.id).toSet();
    expect(ids, containsAll(['delhi', 'faridabad']));
    expect(ids, isNot(contains('mumbai')));
    expect(ids, isNot(contains('chennai')));
    expect(ids, isNot(contains('matched')));
    expect(ids, isNot(contains('own')));
    expect(ids, isNot(contains('nohash')));
  });

  test('backfill adds the field to old loads once and skips unknown places', () async {
    await seedLoad(db, 'old1', 'Pune', geohash: false);
    await seedLoad(db, 'old2', 'Some village', geohash: false);
    await seedLoad(db, 'new1', 'Delhi');
    expect(await LoadService.backfillPickupGeohash(), 1);
    expect((await db.collection('loads').doc('old1').get()).data()!['pickupGeohash'], pickupGeohashFor('Pune'));
    expect(await LoadService.backfillPickupGeohash(), 0);
  });

  testWidgets('a nearby load outside the newest page is still listed, nearest first', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    languageNotifier.value = AppLanguage.english;
    late List<Load> page;
    late Load nearLoad;
    await tester.runAsync(() async {
      await seedLoad(db, 'mumbai', 'Mumbai');
      await seedLoad(db, 'delhi', 'Delhi');
      page = [Load.fromDoc(await db.collection('loads').doc('mumbai').get())];
      nearLoad = Load.fromDoc(await db.collection('loads').doc('delhi').get());
    });

    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(
        home: Scaffold(
          body: AvailableLoadsView(
            loads: (_) => Stream.value(Paged.all(page)),
            nearby: (_) => Stream.value([nearLoad]),
            origin: delhi,
          ),
        ),
      ),
    ));
    await settle(tester);
    expect(find.byKey(const ValueKey('delhi')), findsOneWidget);
    expect(find.byKey(const ValueKey('mumbai')), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const ValueKey('delhi'))).dy, lessThan(tester.getTopLeft(find.byKey(const ValueKey('mumbai'))).dy));
  });
}
