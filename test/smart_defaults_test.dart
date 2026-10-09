import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/drafts/smart_defaults.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/vehicle_type.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/vehicle_type_service.dart';
import 'package:transport_app/customer/post_load_screen.dart';

/// MASTER-6 Task 16: smart defaults on Post Load.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'c1');
    VehicleTypeService.reset();
  });

  const small = VehicleTypeInfo(id: 'S', name: 'Small', minTons: 0.5, maxTons: 1, category: 'lcv');
  const mid = VehicleTypeInfo(id: 'M', name: 'Mid', minTons: 1, maxTons: 4, category: 'lcv');
  const big = VehicleTypeInfo(id: 'B', name: 'Big', minTons: 4, maxTons: 10, category: 'hcv');
  const off = VehicleTypeInfo(id: 'O', name: 'Off', minTons: 0, maxTons: 2, category: 'lcv', active: false);

  test('suggestVehicle: the smallest active type that carries the weight', () {
    final all = [big, off, mid, small];
    expect(SmartDefaults.suggestVehicle(0.8, all)!.id, 'S');
    expect(SmartDefaults.suggestVehicle(1, all)!.id, 'S'); // the edge fits
    expect(SmartDefaults.suggestVehicle(1.01, all)!.id, 'M');
    expect(SmartDefaults.suggestVehicle(4.5, all)!.id, 'B');
    expect(SmartDefaults.suggestVehicle(11, all), isNull);
    expect(SmartDefaults.suggestVehicle(0, all), isNull);
    expect(SmartDefaults.suggestVehicle(null, all), isNull);
    expect(SmartDefaults.suggestVehicle(101, all), isNull);
    expect(SmartDefaults.suggestVehicle(3, [off]), isNull);
  });

  test('presets: newest first, one per goods and vehicle, at most five, junk ignored', () {
    var list = <GoodsPreset>[];
    for (var i = 0; i < 7; i++) {
      list = SmartDefaults.pushPreset(list, GoodsPreset('G$i', 2, 'M'));
    }
    expect(list.map((p) => p.cargo), ['G6', 'G5', 'G4', 'G3', 'G2']);
    list = SmartDefaults.pushPreset(list, const GoodsPreset('G3', 5, 'M'));
    expect(list.first.weight, 5);
    expect(list.map((p) => p.cargo), ['G3', 'G6', 'G5', 'G4', 'G2']);
    expect(GoodsPreset.fromJson({'cargo': 'x', 'weight': -1, 'vehicleType': 'M'}), isNull);
    expect(GoodsPreset.fromJson('x'), isNull);
  });

  test('record keeps the last route and the usual goods per person', () async {
    await SmartDefaults.record(pickup: 'Delhi', drop: 'Jaipur', cargo: 'FMCG', weight: 3, vehicleType: 'M');
    await SmartDefaults.record(pickup: 'Agra', drop: 'Pune', cargo: 'Steel', weight: 8, vehicleType: 'B');
    final r = (await SmartDefaults.lastRoute())!;
    expect((r.pickup, r.drop), ('Agra', 'Pune'));
    expect((await SmartDefaults.presets()).map((p) => p.cargo), ['Steel', 'FMCG']);
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'c2');
    expect(await SmartDefaults.lastRoute(), isNull);
    expect(await SmartDefaults.presets(), isEmpty);
  });

  testWidgets('the form offers the last route and the usual goods, and a vehicle that fits the weight', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    VehicleTypeService.notifier.value = const [small, mid, big];
    await SmartDefaults.record(pickup: 'Delhi', drop: 'Jaipur', cargo: cargoFirst, weight: 3, vehicleType: 'M');
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: PostLoadScreen())));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Last route: Delhi → Jaipur'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sdLastRoute')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Delhi'), findsOneWidget);
    expect(find.byKey(const ValueKey('sdLastRoute')), findsNothing); // once filled, no longer offered
    await tester.tap(find.byKey(const ValueKey('sdPreset_0')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, '3'), findsOneWidget);
  });

  testWidgets('a weight that the chosen vehicle cannot carry (or that a smaller one carries) gets a suggestion', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    VehicleTypeService.notifier.value = const [small, mid, big];
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: PostLoadScreen(initialVehicleType: 'M', initialPickup: 'Delhi'))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sdSuggestVehicle')), findsNothing);
    final weight = find.ancestor(of: find.byIcon(Icons.scale_outlined), matching: find.byType(TextFormField));
    await tester.enterText(weight, '0.8');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sdSuggestVehicle')), findsOneWidget); // Mid carries it, Small is enough
    await tester.tap(find.byKey(const ValueKey('sdSuggestVehicle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sdSuggestVehicle')), findsNothing); // now the smallest fit is chosen
  });
}

// The first cargo type the form knows, so the preset can be applied.
String get cargoFirst => cargoTypes.first;
