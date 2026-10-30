import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/driver/driver_home_screen.dart';
import 'package:transport_app/driver/v2/driver_home_v2.dart';
import 'package:transport_app/driver/v3/driver_home_v3.dart';

/// U27: the new driver home (switch uiV2) and the older one with the switch off.
void main() {
  late FakeFirebaseFirestore db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'driver1', phoneNumber: '+919800000000'));
    Backend.useFakes(db: db, uid: () => 'driver1', auth: () => auth);
    FeaturesService.reset();
    languageNotifier.value = AppLanguage.english;
  });
  tearDown(FeaturesService.reset);

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Widget host({Brightness b = Brightness.light, double scale = 1.0}) => LanguageScope(
        notifier: languageNotifier,
        child: MaterialApp(
          theme: AppTheme.build(b),
          builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
          home: const DriverHomeScreen(),
        ),
      );

  Future<Vehicle> veh(String id) async {
    await db.collection('vehicles').doc(id).set({'number': 'MH12$id', 'type': '14ft', 'capacity': 4});
    return Vehicle.fromDoc(await db.collection('vehicles').doc(id).get());
  }

  test('radarLine: offline, no truck, searching, waiting', () {
    expect(radarLine(online: false, vehicleCount: 2, waiting: 3), RadarLine.offline);
    expect(radarLine(online: true, vehicleCount: 0, waiting: 3), RadarLine.noTruck);
    expect(radarLine(online: true, vehicleCount: 1, waiting: 0), RadarLine.searching);
    expect(radarLine(online: true, vehicleCount: 1, waiting: 2), RadarLine.waiting);
  });

  test('pickVehicle: the chosen truck, else the first, else none', () async {
    final all = [await veh('a'), await veh('b')];
    expect(pickVehicle(all, 'b')!.id, 'b');
    expect(pickVehicle(all, 'gone')!.id, 'a');
    expect(pickVehicle(all, null)!.id, 'a');
    expect(pickVehicle(const [], 'a'), isNull);
  });

  testWidgets('the new home: big online switch, radar line, truck chips; the choice is remembered', (t) async {
    t.view.physicalSize = const Size(360 * 2, 640 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await db.collection('users').doc('driver1').set({'driverName': 'Ramesh'});
    await t.runAsync(() async {
      await VehicleService.add(number: 'MH12AB1234', type: '14ft', capacity: 4, rcNumber: 'RC1');
      await VehicleService.add(number: 'KA01CD5678', type: '20ft', capacity: 9, rcNumber: 'RC2');
    });
    await t.pumpWidget(host());
    await settle(t);
    expect(find.byKey(const ValueKey('dhHero')), findsOneWidget);
    expect(find.text('You are offline'), findsOneWidget);
    expect(find.text('Go online to get loads'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('onlineSwitch')));
    await settle(t);
    expect(find.text('You are online'), findsOneWidget);
    expect(find.text('Looking for loads near you'), findsOneWidget);
    final chips = find.byWidgetPredicate((w) => w is ChoiceChip);
    expect(chips, findsNWidgets(2));
    await t.tap(chips.at(1));
    await settle(t);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('driver_truck_today'), isNotNull);
  });

  testWidgets('no truck: the home says so and offers Add vehicle; dark and 2.0x text do not overflow', (t) async {
    t.view.physicalSize = const Size(360 * 2, 640 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(host(b: Brightness.dark, scale: 2.0));
    await settle(t);
    await t.scrollUntilVisible(find.byKey(const ValueKey('dhNoTruck')), 300, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const ValueKey('dhNoTruck')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('uiV2 OFF: the older home (no DriverHomeV2)', (t) async {
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.uiV2: false});
    await t.pumpWidget(host());
    await settle(t);
    expect(find.byType(DriverHomeV2), findsNothing);
    expect(find.byKey(const ValueKey('onlineSwitch')), findsOneWidget);
  });

  testWidgets('E22: driverHomeV3 ON shows the arrangeable driver home; it needs designV3', (t) async {
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.driverHomeV3: true});
    await t.pumpWidget(host());
    await settle(t);
    expect(find.byType(DriverHomeV3), findsOneWidget);
    expect(find.byType(DriverHomeV2), findsNothing);
    expect(find.byKey(const ValueKey('d3Hero')), findsOneWidget);
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.driverHomeV3: true, FeatureKey.designV3: false});
    await settle(t);
    expect(find.byType(DriverHomeV2), findsOneWidget);
    expect(find.byType(DriverHomeV3), findsNothing);
  });
}
