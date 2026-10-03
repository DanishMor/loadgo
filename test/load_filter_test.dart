import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/load_filter.dart';
import 'package:transport_app/core/models/paged.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/features/loads/available_loads_view.dart';

import 'test_utils.dart';

Future<List<Load>> sampleLoads(FakeFirebaseFirestore db) async {
  final data = [
    ('l1', 'New Delhi', '20ft', 25000),
    ('l2', 'Mumbai', '14ft', 12000),
    ('l3', 'Delhi Cantt', '14ft', null),
    ('l4', 'Pune', 'Trailer', 60000),
  ];
  for (final (id, pickup, type, budget) in data) {
    await db.collection('loads').doc(id).set({
      'shipperId': 'customer1',
      'pickup': pickup,
      'drop': 'Jaipur',
      'cargoType': 'FMCG',
      'weight': 5,
      'vehicleType': type,
      'budget': budget,
      'pickupDate': Timestamp.fromDate(DateTime(2026, 10, 5)),
      'status': 'open',
    });
  }
  return [for (final (id, _, _, _) in data) Load.fromDoc(await db.collection('loads').doc(id).get())];
}

void main() {
  test('LoadFilter matches pickup text, vehicle type and min budget', () async {
    final loads = await sampleLoads(FakeFirebaseFirestore());
    List<String> ids(LoadFilter f) => f.apply(loads).map((l) => l.id).toList();

    expect(ids(LoadFilter.none), ['l1', 'l2', 'l3', 'l4']);
    expect(ids(const LoadFilter(pickupQuery: ' delhi ')), ['l1', 'l3']);
    expect(ids(const LoadFilter(vehicleType: '14ft')), ['l2', 'l3']);
    expect(ids(const LoadFilter(minBudget: 20000)), ['l1', 'l4'], reason: 'negotiable loads drop out');
    expect(ids(const LoadFilter(pickupQuery: 'delhi', vehicleType: '14ft')), ['l3']);
    expect(ids(const LoadFilter(pickupQuery: 'delhi', vehicleType: '14ft', minBudget: 1)), isEmpty);

    expect(LoadFilter.none.isEmpty, isTrue);
    const f = LoadFilter(vehicleType: 'Mini', minBudget: 5);
    expect(f.sheetFilterCount, 2);
    expect(f.copyWith(vehicleType: () => null).vehicleType, isNull);
    expect(f.copyWith(vehicleType: () => null).minBudget, 5);
  });

  testWidgets('search, filter sheet and clear filters', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'driver1');
    late List<Load> loads;
    await tester.runAsync(() async => loads = await sampleLoads(db));

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AvailableLoadsView(loads: (_) => Stream.value(Paged.all(loads))))));
    await settle(tester);
    expect(find.textContaining('→ Jaipur'), findsNWidgets(4));

    await tester.enterText(find.byType(TextField), 'delhi');
    await tester.pump();
    expect(find.text('New Delhi → Jaipur'), findsOneWidget);
    expect(find.text('Delhi Cantt → Jaipur'), findsOneWidget);
    expect(find.text('Mumbai → Jaipur'), findsNothing);

    // Filter sheet: 14ft + min budget 1 -> nothing matches.
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vehicleTypeFilter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('14ft').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('minBudgetFilter')), '1');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.text('No loads match your filters'), findsOneWidget);
    expect(find.text('14ft'), findsOneWidget, reason: 'active filter chip');
    expect(find.text('≥ ₹ 1'), findsOneWidget);

    // Removing the budget chip brings back the 14ft Delhi load.
    await tester.tap(find.descendant(of: find.widgetWithText(InputChip, '≥ ₹ 1'), matching: find.byType(Icon)).last);
    await tester.pumpAndSettle();
    expect(find.text('Delhi Cantt → Jaipur'), findsOneWidget);
    expect(find.text('New Delhi → Jaipur'), findsNothing);

    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('New Delhi → Jaipur'), findsOneWidget, reason: 'search text is kept');
    expect(find.text('Delhi Cantt → Jaipur'), findsOneWidget);
  });
}
