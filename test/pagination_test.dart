import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/models/paged.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/driver/available_loads_view.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;

  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'driver1');
  });

  Future<void> seedLoads(int n, {String shipper = 'customer1'}) async {
    for (var i = 0; i < n; i++) {
      await db.collection('loads').add({
        'shipperId': shipper,
        'pickup': 'City $i',
        'drop': 'Mumbai',
        'cargoType': 'FMCG',
        'weight': 5,
        'vehicleType': '20ft',
        'budget': 1000,
        'status': 'open',
        'createdAt': DateTime(2026, 1, 1).add(Duration(minutes: i)),
      });
    }
  }

  test('open page returns the newest N and says whether more exist', () async {
    await seedLoads(25);
    final first = await LoadService.watchOpenPage(pageSize).first;
    expect(first.items, hasLength(pageSize));
    expect(first.hasMore, isTrue);
    expect(first.items.first.pickup, 'City 24');

    final all = await LoadService.watchOpenPage(pageSize * 2).first;
    expect(all.items, hasLength(25));
    expect(all.hasMore, isFalse);
  });

  test('own loads are hidden from the driver page but still count towards the page', () async {
    await seedLoads(3, shipper: 'driver1');
    final page = await LoadService.watchOpenPage(3).first;
    expect(page.items, isEmpty);
    expect(page.hasMore, isTrue);
  });

  testWidgets('Available Loads shows 20, then Load more reveals the rest', (tester) async {
    tester.view.physicalSize = const Size(800, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => seedLoads(25));

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AvailableLoadsView(loads: LoadService.watchOpenPage))));
    await settle(tester);
    expect(find.text('Load more'), findsOneWidget);
    Finder city(int i) => find.textContaining('City $i ', skipOffstage: false);
    expect(city(24), findsWidgets);
    expect(city(5), findsWidgets); // 20th newest
    expect(city(4), findsNothing); // 21st newest

    await tester.ensureVisible(find.text('Load more'));
    await tester.tap(find.text('Load more'));
    await settle(tester);
    expect(find.text('Load more'), findsNothing);
    expect(city(0), findsWidgets);
  });
}
