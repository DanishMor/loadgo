import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_supply_demand_screen.dart';
import 'package:transport_app/core/admin/staff_roles.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/l10n/supply_demand_strings.dart';
import 'package:transport_app/core/matching/supply_demand.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/services/admin_console_service.dart';
import 'package:transport_app/core/services/backend.dart';

import 'test_utils.dart';

Vehicle veh(String id, {String owner = 'd1', String type = 'lcv', String status = 'active', String availability = 'available', String? assigned}) =>
    Vehicle(id: id, ownerId: owner, number: 'MH12$id', type: type, capacity: 5, rcNumber: 'R', status: status, availability: availability, assignedDriverId: assigned);

void main() {
  late FakeFirebaseFirestore db;
  const delhi = (lat: 28.61, lng: 77.21);
  const mumbai = (lat: 19.07, lng: 72.88);
  const nowhere = (lat: 0.0, lng: 0.0);

  setUp(() {
    languageNotifier.value = AppLanguage.english;
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'admin1');
  });

  Future<List<Load>> loads(List<(String, String, String)> specs) async {
    final out = <Load>[];
    var i = 0;
    for (final s in specs) {
      final id = 'L${i++}';
      await db.collection('loads').doc(id).set({'shipperId': 'c', 'pickup': s.$1, 'drop': 'Jaipur', 'vehicleType': s.$2, 'status': s.$3, 'cargoType': 'x', 'weight': 1});
      out.add(Load.fromDoc(await db.collection('loads').doc(id).get()));
    }
    return out;
  }

  group('SupplyDemand.compute', () {
    test('loads and free trucks are counted per city; the biggest gap comes first', () async {
      final l = await loads([('Delhi', 'lcv', 'open'), ('Delhi', 'lcv', 'open'), ('Delhi', 'truck', 'open'), ('Mumbai', 'lcv', 'open'), ('Delhi', 'lcv', 'closed')]);
      final spots = {'d1': delhi, 'd2': mumbai, 'd3': mumbai};
      final r = SupplyDemand.compute(l, [veh('a', owner: 'd1'), veh('b', owner: 'd2'), veh('c', owner: 'd3')], (v) => spots[v.ownerId]);
      expect(r.totalDemand, 4, reason: 'the closed load is not demand');
      expect(r.totalSupply, 3);
      expect(r.cities.map((c) => (c.city, c.demand, c.supply)), [('Delhi', 3, 1), ('Mumbai', 1, 2)]);
      expect(r.types['lcv']!.demand, 3);
      expect(r.types['lcv']!.supply, 3);
      expect(r.types['truck']!.demand, 1);
      expect(r.types['truck']!.supply, 0);
    });

    test('only active and available vehicles are supply', () {
      final r = SupplyDemand.compute(const [], [
        veh('a'), veh('b', availability: 'on_trip'), veh('c', availability: 'maintenance'), veh('d', status: 'inactive'), veh('e', availability: 'doc_expired'),
      ], (_) => delhi);
      expect(r.totalSupply, 1);
    });

    test('a truck with no position, or far from every city, is counted but not placed', () {
      final r = SupplyDemand.compute(const [], [veh('a'), veh('b')], (v) => v.id == 'a' ? null : nowhere);
      expect(r.totalSupply, 2);
      expect(r.unlocatedSupply, 2);
      expect(r.cities, isEmpty);
    });

    test('pickups outside the city table go to the "other" row', () async {
      final l = await loads([('Some Village', 'lcv', 'open')]);
      final r = SupplyDemand.compute(l, const [], (_) => null);
      expect(r.cities.single.city, '');
    });

    test('balance: short, balanced, surplus', () {
      expect(const SupplyDemandRow(city: 'a', demand: 3, supply: 1).balance, Balance.short);
      expect(const SupplyDemandRow(city: 'a', demand: 2, supply: 1).balance, Balance.balanced);
      expect(const SupplyDemandRow(city: 'a', demand: 1, supply: 3).balance, Balance.surplus);
      expect(const SupplyDemandRow(city: 'a', demand: 0, supply: 0).balance, Balance.balanced);
      expect(const SupplyDemandRow(city: 'a', demand: 1, supply: 0).balance, Balance.short);
      expect(const SupplyDemandRow(city: 'a', demand: 0, supply: 1).balance, Balance.surplus);
    });
  });

  group('AdminConsoleService.supplyDemand', () {
    test('reads open loads, available vehicles and driver positions; a fleet driver position wins over the owner', () async {
      await db.collection('users').doc('owner1').set({'role': 'driver', 'lastLocation': {'lat': delhi.lat, 'lng': delhi.lng}});
      await db.collection('users').doc('fleetDriver').set({'role': 'driver', 'lastLocation': {'lat': mumbai.lat, 'lng': mumbai.lng}});
      await db.collection('vehicles').doc('v1').set({'ownerId': 'owner1', 'assignedDriverId': 'fleetDriver', 'number': 'A', 'type': 'lcv', 'capacity': 3, 'status': 'active', 'availability': 'available'});
      await db.collection('vehicles').doc('v2').set({'ownerId': 'owner1', 'number': 'B', 'type': 'lcv', 'capacity': 3, 'status': 'active', 'availability': 'on_trip'});
      await db.collection('loads').doc('l1').set({'shipperId': 'c', 'pickup': 'Mumbai', 'drop': 'Pune', 'vehicleType': 'lcv', 'status': 'open', 'cargoType': 'x', 'weight': 1});
      final r = await AdminConsoleService.supplyDemand();
      expect(r.cities.single.city, 'Mumbai');
      expect((r.cities.single.demand, r.cities.single.supply), (1, 1));
      expect(r.totalSupply, 1);
    });
  });

  group('AdminSupplyDemandScreen', () {
    Future<void> open(WidgetTester t, Future<SupplyDemand> Function() load) async {
      t.view.physicalSize = const Size(800, 2000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(home: LanguageScope(notifier: languageNotifier, child: AdminSupplyDemandScreen(load: load))));
      await settle(t);
    }

    testWidgets('shows totals, cities with a balance chip, and types', (t) async {
      final l = await t.runAsync(() => loads([('Delhi', 'lcv', 'open'), ('Delhi', 'lcv', 'open'), ('Delhi', 'lcv', 'open')]));
      final r = SupplyDemand.compute(l!, [veh('a')], (_) => delhi);
      await open(t, () async => r);
      expect(find.text('3 open loads, 1 free trucks (0 without a known position)'), findsOneWidget);
      expect(find.byKey(const ValueKey('sdCity_Delhi')), findsOneWidget);
      expect(find.text('Trucks short'), findsWidgets);
      expect(find.text('3 open loads, 1 free trucks'), findsWidgets);
    });

    testWidgets('empty state', (t) async {
      await open(t, () async => SupplyDemand.compute(const [], const [], (_) => null));
      expect(find.text('No open loads and no free trucks right now'), findsOneWidget);
    });

    testWidgets('an error shows Retry, which loads again', (t) async {
      var n = 0;
      await open(t, () async {
        n++;
        if (n == 1) throw StateError('x');
        return SupplyDemand.compute(const [], const [], (_) => null);
      });
      expect(find.text('Retry'), findsOneWidget);
      await t.tap(find.text('Retry'));
      await settle(t);
      expect(find.text('No open loads and no free trucks right now'), findsOneWidget);
    });
  });

  test('staff area: super and ops', () {
    expect(staffCan('super', 'adminSupplyDemand'), isTrue);
    expect(staffCan('ops', 'adminSupplyDemand'), isTrue);
    expect(staffCan('support', 'adminSupplyDemand'), isFalse);
  });

  test('supply and demand strings: 12 languages, same placeholders', () {
    final ph = RegExp(r'\{(\w+)\}');
    for (final e in supplyDemandStrings.entries) {
      expect(e.value.length, 12, reason: e.key);
      expect(e.value.every((s) => s.trim().isNotEmpty), isTrue, reason: e.key);
      final want = ph.allMatches(e.value[0]).map((m) => m[1]).toSet();
      for (var i = 1; i < 12; i++) {
        expect(ph.allMatches(e.value[i]).map((m) => m[1]).toSet(), want, reason: '${e.key}/$i');
      }
    }
  });
}
