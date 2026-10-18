import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/matching/nearest.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/paged.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/driver/available_loads_view.dart';
import 'package:transport_app/driver/driver_location_sync.dart';
import 'package:transport_app/driver/v2/loads_feed_v2.dart';

import 'test_utils.dart';

/// U30: the driver's feed with uiV2: sort chips, saved routes, and the old feed when the switch is off.
Load mk(String id, num budget, DateTime created, {String pickup = 'Delhi'}) => Load(
      id: id,
      shipperId: 'c1',
      pickup: pickup,
      drop: 'Jaipur',
      cargoType: 'FMCG',
      weight: 4,
      vehicleType: '14ft',
      budget: budget,
      pickupDate: null,
      notes: '',
      status: 'open',
      createdAt: Timestamp.fromDate(created),
    );

void main() {
  final t0 = DateTime(2030, 1, 1);

  test('sortFeed: best pay is dearest first, newest is latest first, nearest keeps the order; ties keep the order', () {
    final a = NearLoad(mk('a', 10000, t0), 5), b = NearLoad(mk('b', 30000, t0.add(const Duration(hours: 1))), 9), c = NearLoad(mk('c', 30000, t0.add(const Duration(hours: 2))), 2);
    final items = [a, b, c];
    expect(sortFeed(items, FeedSort.nearest).map((e) => e.load.id), ['a', 'b', 'c']);
    expect(sortFeed(items, FeedSort.bestPay).map((e) => e.load.id), ['b', 'c', 'a']);
    expect(sortFeed(items, FeedSort.newest).map((e) => e.load.id), ['c', 'b', 'a']);
  });

  group('screen', () {
    late FakeFirebaseFirestore db;
    setUp(() {
      db = FakeFirebaseFirestore();
      Backend.useFakes(db: db, uid: () => 'driver1');
      DriverLocationSync.resetForTest();
      FeaturesService.reset();
      languageNotifier.value = AppLanguage.english;
    });
    tearDown(FeaturesService.reset);

    Future<void> show(WidgetTester t, List<Load> loads) async {
      t.view.physicalSize = const Size(360 * 2, 1400 * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(LanguageScope(
        notifier: languageNotifier,
        child: MaterialApp(home: Scaffold(body: AvailableLoadsView(loads: (_) => Stream.value(Paged.all(loads)), origin: (lat: 28.61, lng: 77.21)))),
      ));
      await settle(t);
    }

    testWidgets('uiV2 on: sort chips show and Best pay puts the dearest load first', (t) async {
      final loads = [mk('cheap', 10000, t0), mk('dear', 30000, t0)];
      await show(t, loads);
      expect(find.byKey(const ValueKey('fdSort')), findsOneWidget);
      double top(String id) => t.getTopLeft(find.byKey(ValueKey(id))).dy;
      expect(top('cheap') < top('dear'), isTrue);
      await t.tap(find.text('Best pay'));
      await settle(t);
      expect(top('dear') < top('cheap'), isTrue);
    });

    testWidgets('uiV2 off: the old feed, without the sort chips', (t) async {
      FeaturesService.notifier.value = const Features(flags: {FeatureKey.uiV2: false});
      await show(t, [mk('a', 10000, t0)]);
      expect(find.byKey(const ValueKey('fdSort')), findsNothing);
      expect(find.byKey(const ValueKey('a')), findsOneWidget);
    });

    testWidgets('a saved route is a chip; tapping it filters the feed', (t) async {
      await t.runAsync(() => db.collection('users').doc('driver1').collection('favourite_routes').doc('x').set({'pickup': 'Delhi', 'drop': 'Mumbai'}));
      await show(t, [mk('jp', 10000, t0)]);
      expect(find.byKey(const ValueKey('fdRoutes')), findsOneWidget);
      await t.tap(find.text('Delhi → Mumbai'));
      await settle(t);
      expect(find.byKey(const ValueKey('jp')), findsNothing, reason: 'Jaipur load does not go to Mumbai');
    });

    testWidgets('removing the drop chip unlights the saved route chip', (t) async {
      await t.runAsync(() => db.collection('users').doc('driver1').collection('favourite_routes').doc('x').set({'pickup': 'Delhi', 'drop': 'Mumbai'}));
      await show(t, [mk('jp', 10000, t0)]);
      await t.tap(find.text('Delhi → Mumbai'));
      await settle(t);
      expect(t.widget<FeedHeaderV2>(find.byType(FeedHeaderV2)).route, isNotNull);
      final chip = find.widgetWithText(InputChip, '→ Mumbai');
      expect(chip, findsOneWidget);
      t.widget<InputChip>(chip).onDeleted!();
      await settle(t);
      expect(t.widget<FeedHeaderV2>(find.byType(FeedHeaderV2)).route, isNull);
    });
  });
}
