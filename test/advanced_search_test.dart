import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/load_filter.dart';
import 'package:transport_app/core/models/paged.dart';
import 'package:transport_app/core/models/saved_search.dart';
import 'package:transport_app/core/models/truck_board.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/saved_search_service.dart';
import 'package:transport_app/customer/truck_board_screen.dart';
import 'package:transport_app/driver/available_loads_view.dart';

import 'test_utils.dart';

Future<List<Load>> loadsOf(FakeFirebaseFirestore db) async {
  // id, pickup, drop, weight, budget, day
  final data = [
    ('l1', 'Pune', 'Delhi', 5, 20000, 5),
    ('l2', 'Pune', 'Mumbai', 12, 50000, 8),
    ('l3', 'Surat', 'Delhi', 2, null, 12),
    ('l4', 'Pune', 'Delhi', 9, 90000, 20),
  ];
  for (final (id, pickup, drop, weight, budget, day) in data) {
    await db.collection('loads').doc(id).set({
      'shipperId': 'c1', 'pickup': pickup, 'drop': drop, 'cargoType': 'FMCG', 'weight': weight, 'vehicleType': '20ft',
      'budget': budget, 'pickupDate': Timestamp.fromDate(DateTime(2026, 10, day)), 'status': 'open',
    });
  }
  return [for (final d in data) Load.fromDoc(await db.collection('loads').doc(d.$1).get())];
}

TruckPost post(String id, String from, String to, num cap, int day) => TruckPost(
      id: id, driverId: 'd', vehicleId: 'v', vehicleNumber: 'MH12AB1234', vehicleType: '20ft', capacity: cap, fromCity: from, toCity: to,
      availableDate: DateTime(2026, 10, day), status: 'open',
    );

void main() {
  test('LoadFilter: drop, weight, budget and date ranges combine; no budget or date drops out of a range', () async {
    final loads = await loadsOf(FakeFirebaseFirestore());
    List<String> ids(LoadFilter f) => f.apply(loads).map((l) => l.id).toList();
    expect(ids(const LoadFilter(dropQuery: ' delhi ')), ['l1', 'l3', 'l4']);
    expect(ids(const LoadFilter(minWeight: 5, maxWeight: 10)), ['l1', 'l4']);
    expect(ids(const LoadFilter(maxBudget: 50000)), ['l1', 'l2'], reason: 'negotiable load drops out');
    expect(ids(const LoadFilter(minBudget: 20000, maxBudget: 60000)), ['l1', 'l2']);
    expect(ids(LoadFilter(fromDate: DateTime(2026, 10, 8), toDate: DateTime(2026, 10, 12))), ['l2', 'l3']);
    expect(ids(LoadFilter(fromDate: DateTime(2026, 10, 20))), ['l4']);
    expect(ids(LoadFilter(pickupQuery: 'pune', dropQuery: 'delhi', minWeight: 6, toDate: DateTime(2026, 10, 31))), ['l4']);
    expect(const LoadFilter(dropQuery: 'x', minWeight: 1, maxWeight: 2, minBudget: 1, maxBudget: 2, vehicleType: 'a').sheetFilterCount, 6);
  });

  test('filters survive the saved form (maps round-trip)', () {
    final f = LoadFilter(pickupQuery: 'Pune', dropQuery: 'Delhi', vehicleType: '20ft', minBudget: 1000, maxBudget: 5000, minWeight: 2, maxWeight: 9.5, fromDate: DateTime(2026, 10, 1), toDate: DateTime(2026, 10, 9));
    final back = LoadFilter.fromMap(f.toMap());
    expect(back.toMap(), f.toMap());
    expect((back.fromDate, back.toDate, back.maxWeight), (DateTime(2026, 10, 1), DateTime(2026, 10, 9), 9.5));
    expect(LoadFilter.none.toMap(), isEmpty);
    expect(parseIsoDate('2026-13-45x'), isNull);
    final t = TruckFilter(from: 'Pune', vehicleType: '20ft', minCapacity: 10, onOrAfter: DateTime(2026, 10, 3));
    expect(TruckFilter.fromMap(t.toMap()).toMap(), t.toMap());
  });

  test('TruckFilter: minimum capacity and dates', () {
    final posts = [post('a', 'Pune', 'Delhi', 9, 5), post('b', 'Pune', 'Delhi', 20, 9), post('c', 'Surat', 'Delhi', 20, 15)];
    List<String> ids(TruckFilter f) => [for (final p in posts) if (f.matches(p)) p.id];
    expect(ids(const TruckFilter(minCapacity: 10)), ['b', 'c']);
    expect(ids(TruckFilter(minCapacity: 10, onOrBefore: DateTime(2026, 10, 10))), ['b']);
    expect(ids(TruckFilter(from: 'pune', onOrAfter: DateTime(2026, 10, 6))), ['b']);
  });

  group('saved searches', () {
    late FakeFirebaseFirestore db;
    setUp(() {
      db = FakeFirebaseFirestore();
      Backend.useFakes(db: db, uid: () => 'u1');
    });

    test('save, list per kind sorted, delete, cap of 10 per kind, validation', () async {
      await SavedSearchService.save(kind: SearchKind.loads, name: 'b Pune', filter: const LoadFilter(pickupQuery: 'Pune').toMap());
      await SavedSearchService.save(kind: SearchKind.loads, name: 'A Delhi', filter: const LoadFilter(dropQuery: 'Delhi').toMap());
      await SavedSearchService.save(kind: SearchKind.trucks, name: 'Trucks', filter: const TruckFilter(from: 'Pune').toMap());
      final loads = await SavedSearchService.watch(SearchKind.loads).first;
      expect(loads.map((s) => s.name), ['A Delhi', 'b Pune']);
      expect((await SavedSearchService.watch(SearchKind.trucks).first).single.name, 'Trucks');
      expect(LoadFilter.fromMap(loads.first.filter).dropQuery, 'Delhi');
      await SavedSearchService.delete(loads.first.id);
      expect((await SavedSearchService.watch(SearchKind.loads).first).length, 1);

      expect(() => SavedSearchService.save(kind: SearchKind.loads, name: ' ', filter: const {'pickup': 'x'}), throwsArgumentError);
      expect(() => SavedSearchService.save(kind: SearchKind.loads, name: 'x', filter: const {}), throwsArgumentError);
      expect(() => SavedSearchService.save(kind: 'bogus', name: 'x', filter: const {'pickup': 'x'}), throwsArgumentError);
      for (var i = 1; i < SavedSearch.maxPerKind; i++) {
        await SavedSearchService.save(kind: SearchKind.loads, name: 'n$i', filter: {'pickup': 'p$i'});
      }
      await expectLater(SavedSearchService.save(kind: SearchKind.loads, name: 'one more', filter: const {'pickup': 'z'}), throwsA(isA<SearchLimitException>()));
      await SavedSearchService.save(kind: SearchKind.trucks, name: 'other kind is separate', filter: const {'from': 'z'});
    });

    testWidgets('driver: new filters in the sheet, save the search, clear, apply it again', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late List<Load> loads;
      await tester.runAsync(() async => loads = await loadsOf(db));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: AvailableLoadsView(loads: (_) => Stream.value(Paged.all(loads))))));
      await settle(tester);
      expect(find.textContaining('→'), findsWidgets);

      await tester.tap(find.byIcon(Icons.tune_rounded));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('dropFilter')), 'delhi');
      await tester.enterText(find.byKey(const ValueKey('minWeightFilter')), '6');
      await tester.tap(find.byKey(const ValueKey('applyFilters')));
      await settle(tester);
      expect(find.text('Pune → Delhi'), findsOneWidget); // l4 only (weight 9)
      expect(find.text('Surat → Delhi'), findsNothing);
      expect(find.text('Pune → Mumbai'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('saveSearch')));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('searchName')), 'Heavy to Delhi');
      await tester.tap(find.byKey(const ValueKey('searchNameOk')));
      await settle(tester);
      expect((await db.collection('users').doc('u1').collection('saved_searches').get()).docs.single['name'], 'Heavy to Delhi');

      // clear all, then apply the saved one
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await settle(tester);
      await tester.tap(find.text('Clear filters'));
      await settle(tester);
      expect(find.text('Pune → Mumbai'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('openSavedSearches')));
      await settle(tester);
      await tester.tap(find.text('Heavy to Delhi'));
      await settle(tester);
      expect(find.text('Pune → Mumbai'), findsNothing);
      expect(find.text('Pune → Delhi'), findsOneWidget);
    });

    testWidgets('truck board: capacity filter and Load more after one page', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final posts = [for (var i = 0; i < 25; i++) post('p$i', 'Pune', 'Delhi', i < 5 ? 5 : 20, 5)];
      await tester.pumpWidget(MaterialApp(home: TruckBoardScreen(posts: Stream.value(posts))));
      await settle(tester);
      expect(find.byKey(const ValueKey('truckPost_p0')), findsOneWidget);
      expect(find.byKey(const ValueKey('truckPost_p24')), findsNothing);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('boardLoadMore')), 300, scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
      await tester.ensureVisible(find.byKey(const ValueKey('boardLoadMore')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('boardLoadMore')));
      await settle(tester);
      expect(find.byKey(const ValueKey('boardLoadMore')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('boardCapacity')), '10');
      await tester.pump();
      expect(find.byKey(const ValueKey('truckPost_p0')), findsNothing);
      expect(find.byKey(const ValueKey('truckPost_p10')), findsOneWidget);
    });
  });
}
