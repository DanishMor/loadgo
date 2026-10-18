import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/dispatch/dispatch_config_service.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/paged.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/driver/available_loads_view.dart';
import 'package:transport_app/driver/driver_location_sync.dart';

import 'test_utils.dart';

/// U11: the driver's feed follows the rings when `dispatchV2` is on, and is untouched when it is off.
Future<Load> load(FakeFirebaseFirestore db, String id, String pickup, DateTime createdAt, {String? mode}) async {
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
    'createdAt': Timestamp.fromDate(createdAt),
    'mode': ?mode,
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
    FeaturesService.reset();
    DispatchConfigService.reset();
    languageNotifier.value = AppLanguage.english;
  });
  tearDown(() {
    FeaturesService.reset();
  });

  Future<void> show(WidgetTester t, List<Load> loads) async {
    t.view.physicalSize = const Size(800, 3000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(home: Scaffold(body: AvailableLoadsView(loads: (_) => Stream.value(Paged.all(loads)), origin: delhi))),
    ));
    await settle(t);
  }

  testWidgets('switch off: every open load is listed as before', (t) async {
    late List<Load> loads;
    await t.runAsync(() async {
      loads = [await load(db, 'delhi', 'Delhi', DateTime.now()), await load(db, 'chennai', 'Chennai', DateTime.now())];
    });
    await show(t, loads);
    expect(find.byKey(const ValueKey('delhi')), findsOneWidget);
    expect(find.byKey(const ValueKey('chennai')), findsOneWidget);
  });

  testWidgets('switch on: a load outside every ring is not listed, a load in the first ring is', (t) async {
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.dispatchV2: true});
    late List<Load> loads;
    await t.runAsync(() async {
      loads = [await load(db, 'delhi', 'Delhi', DateTime.now()), await load(db, 'chennai', 'Chennai', DateTime.now())];
    });
    await show(t, loads);
    expect(find.byKey(const ValueKey('delhi')), findsOneWidget);
    expect(find.byKey(const ValueKey('chennai')), findsNothing);
  });

  testWidgets('switch on: a scheduled load in range is listed at once', (t) async {
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.dispatchV2: true});
    late List<Load> loads;
    await t.runAsync(() async {
      loads = [await load(db, 'delhi', 'Delhi', DateTime.now(), mode: 'scheduled')];
    });
    await show(t, loads);
    expect(find.byKey(const ValueKey('delhi')), findsOneWidget);
  });
}
