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
import 'package:transport_app/core/services/location_service.dart';
import 'package:transport_app/core/services/user_service.dart';
import 'package:transport_app/driver/available_loads_view.dart';
import 'package:transport_app/driver/driver_location_sync.dart';

import 'test_utils.dart';

Future<Load> load(FakeFirebaseFirestore db, String id, String pickup) async {
  await db.collection('loads').doc(id).set({
    'shipperId': 'customer1',
    'pickup': pickup,
    'drop': 'Kolkata',
    'cargoType': 'FMCG',
    'weight': 5,
    'vehicleType': '20ft',
    'budget': 20000,
    'pickupDate': Timestamp.fromDate(DateTime(2026, 10, 5)),
    'status': 'open',
  });
  return Load.fromDoc(await db.collection('loads').doc(id).get());
}

const delhi = (lat: 28.61, lng: 77.21);

void main() {
  late FakeFirebaseFirestore db;
  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'driver1');
    DriverLocationSync.resetForTest();
  });
  tearDown(() => LocationService.useFakeCurrent(null));

  test('geohash matches the reference values', () {
    expect(geohashEncode(57.64911, 10.40744, precision: 11), 'u4pruydqqvj');
    expect(geohashEncode(42.6, -5.6, precision: 5), 'ezs42');
    expect(geohashEncode(28.61, 77.21).length, 9);
    // nearby points share a prefix, far ones do not
    expect(geohashEncode(28.6139, 77.2090).substring(0, 5), geohashEncode(28.6200, 77.2100).substring(0, 5));
    expect(geohashEncode(19.07, 72.87).substring(0, 2), isNot(geohashEncode(28.61, 77.21).substring(0, 2)));
    expect(() => geohashEncode(95, 0), throwsArgumentError);
  });

  test('sorts by distance from the driver, unknown places last, ties keep order', () async {
    final loads = [
      await load(db, 'mumbai', 'Mumbai'),
      await load(db, 'nowhere', 'Some village'),
      await load(db, 'jaipur', 'Jaipur'),
      await load(db, 'delhi', 'New Delhi'),
      await load(db, 'delhi2', 'Delhi'),
    ];
    final sorted = sortNearestFirst(loads, delhi);
    expect(sorted.map((e) => e.load.id), ['delhi', 'delhi2', 'jaipur', 'mumbai', 'nowhere']);
    expect(sorted[0].km, lessThan(sorted[2].km!));
    expect(sorted[2].km, inInclusiveRange(250, 350)); // Delhi-Jaipur by road
    expect(sorted.last.km, isNull);
    expect(sorted[0].km, greaterThanOrEqualTo(1));
  });

  test('driver location is saved with a geohash and read back', () async {
    await UserService.saveDriverLocation(28.61, 77.21);
    final user = (await db.collection('users').doc('driver1').get()).data()!;
    final loc = user['lastLocation'] as Map;
    expect(loc['geohash'], geohashEncode(28.61, 77.21));
    expect(UserService.lastLocationOf(user), (lat: 28.61, lng: 77.21));
    expect(UserService.lastLocationOf({}), isNull);
  });

  test('location sync saves, throttles, and does nothing without a fix', () async {
    LocationService.useFakeCurrent(() async => null);
    expect(await DriverLocationSync.refresh(), isFalse);
    expect((await db.collection('users').doc('driver1').get()).exists, isFalse);

    LocationService.useFakeCurrent(() async => delhi);
    await db.collection('users').doc('driver1').set({'consents': {'location': true}});
    final t = DateTime(2026, 10, 4, 10);
    expect(await DriverLocationSync.refresh(now: t), isTrue);
    expect(await DriverLocationSync.refresh(now: t.add(const Duration(minutes: 1))), isFalse);
    expect(await DriverLocationSync.refresh(now: t.add(const Duration(minutes: 6))), isTrue);
  });

  test('kmAway is translated everywhere', () {
    for (final lang in AppLanguage.values) {
      expect(T.get('kmAway', lang).contains('{n}'), isTrue, reason: lang.name);
    }
  });

  testWidgets('Available Loads lists the nearest first with "X km away"', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    languageNotifier.value = AppLanguage.english;
    late List<Load> loads;
    await tester.runAsync(() async {
      loads = [await load(db, 'mumbai', 'Mumbai'), await load(db, 'jaipur', 'Jaipur'), await load(db, 'delhi', 'Delhi')];
    });

    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(home: Scaffold(body: AvailableLoadsView(loads: (_) => Stream.value(Paged.all(loads)), origin: delhi))),
    ));
    await settle(tester);

    final order = [for (final id in ['delhi', 'jaipur', 'mumbai']) tester.getTopLeft(find.byKey(ValueKey(id))).dy];
    expect(order[0], lessThan(order[1]));
    expect(order[1], lessThan(order[2]));
    expect(find.textContaining(RegExp(r'^\d+ km away$')), findsNWidgets(3));
  });

  testWidgets('without a known position the list keeps its order and shows no distance', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    languageNotifier.value = AppLanguage.english;
    late List<Load> loads;
    await tester.runAsync(() async {
      loads = [await load(db, 'mumbai', 'Mumbai'), await load(db, 'delhi', 'Delhi')];
    });
    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(home: Scaffold(body: AvailableLoadsView(loads: (_) => Stream.value(Paged.all(loads))))),
    ));
    await settle(tester);
    expect(find.textContaining('km away'), findsNothing);
    expect(tester.getTopLeft(find.byKey(const ValueKey('mumbai'))).dy, lessThan(tester.getTopLeft(find.byKey(const ValueKey('delhi'))).dy));
  });

  testWidgets('the saved profile location is used when no origin is passed', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    languageNotifier.value = AppLanguage.english;
    late List<Load> loads;
    await tester.runAsync(() async {
      await UserService.saveDriverLocation(delhi.lat, delhi.lng);
      loads = [await load(db, 'mumbai', 'Mumbai'), await load(db, 'delhi', 'Delhi')];
    });
    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(home: Scaffold(body: AvailableLoadsView(loads: (_) => Stream.value(Paged.all(loads))))),
    ));
    await settle(tester);
    expect(find.textContaining(RegExp(r'^\d+ km away$')), findsNWidgets(2));
    expect(tester.getTopLeft(find.byKey(const ValueKey('delhi'))).dy, lessThan(tester.getTopLeft(find.byKey(const ValueKey('mumbai'))).dy));
  });
}
