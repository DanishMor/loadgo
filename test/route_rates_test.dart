import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/pricing/cities.dart';
import 'package:transport_app/core/pricing/route_rates.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/theme/app_theme.dart';

void main() {
  late FakeFirebaseFirestore db;
  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'c1');
    RouteRates.clearCache();
    languageNotifier.value = AppLanguage.english;
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.rateRange: true});
  });
  tearDown(FeaturesService.reset);

  group('percentiles', () {
    test('the middle half of the amounts, rounded to ten rupees', () {
      final r = RouteRates.fromDoc({'n': 12, 'recent': [4000000, 4100000, 4200000, 4300000, 4400000, 4500000, 4600000, 4700000, 4800000, 4900000, 5000000, 5100000]})!;
      expect(r.low, 4200000);
      expect(r.mid, 4500000);
      expect(r.high, 4800000);
      expect(r.trips, 12);
    });

    test('fewer than five trips, junk or no document give no range', () {
      expect(RouteRates.fromDoc({'recent': [1, 2, 3, 4]}), isNull);
      expect(RouteRates.fromDoc({'recent': 'x'}), isNull);
      expect(RouteRates.fromDoc({'recent': [-5, 0, 1.5, 'a', null, 1000]}), isNull);
      expect(RouteRates.fromDoc(null), isNull);
    });

    test('a count smaller than the list is not trusted', () {
      final r = RouteRates.fromDoc({'n': 1, 'recent': [100000, 100000, 100000, 100000, 100000]})!;
      expect(r.trips, 5);
    });
  });

  test('the key is the same as the server builds it', () {
    expect(RouteRates.keyFor('Andheri, Mumbai', 'jaipur', '14ft'), 'mumbai_jaipur_14ft');
    expect(RouteRates.keyFor('Bombay', 'Delhi', '20 ft Container'), 'mumbai_delhi_20ftcontainer');
    expect(RouteRates.keyFor('Nowhereville', 'Delhi', '14ft'), isNull);
    expect(RouteRates.keyFor('Delhi', 'Delhi', '14ft'), isNull);
    expect(RouteRates.keyFor('Delhi', 'Pune', ''), isNull);
  });

  test('the server and the app read the same city table', () {
    final js = File('functions/src/cities.js').readAsStringSync();
    for (final c in indianCities) {
      expect(js, contains('"name": "${c.name}"'), reason: c.name);
      for (final a in c.aliases) {
        expect(js, contains('"$a"'), reason: a);
      }
    }
    expect(RegExp(r'"name":').allMatches(js).length, indianCities.length, reason: 'run: node tool/gen_cities_js.js');
  });

  test('fetch reads one document, remembers it, and a missing document is no range', () async {
    await db.collection('route_rates').doc('mumbai_jaipur_14ft').set({'n': 5, 'recent': [4000000, 4100000, 4200000, 4300000, 4400000]});
    final a = await RouteRates.fetch('Mumbai', 'Jaipur', '14ft');
    expect(a!.mid, 4200000);
    await db.collection('route_rates').doc('mumbai_jaipur_14ft').delete();
    expect((await RouteRates.fetch('Mumbai', 'Jaipur', '14ft'))!.mid, 4200000, reason: 'one read per route and run');
    expect(await RouteRates.fetch('Mumbai', 'Pune', '14ft'), isNull);
    expect(await RouteRates.fetch('Nowhereville', 'Pune', '14ft'), isNull);
  });

  Widget app(Widget child) => MaterialApp(theme: AppTheme.build(Brightness.light), home: Scaffold(body: child));

  testWidgets('the line shows the range and the number of trips; nothing without a range or with the switch off', (tester) async {
    Future<RateRange?> r(RateRange? v) => Future.value(v);
    await tester.pumpWidget(app(RateRangeLine(pickup: 'Mumbai', drop: 'Jaipur', vehicleType: '14ft', source: r(const RateRange(4200000, 4500000, 4800000, 30)))));
    await tester.pump();
    expect(find.textContaining('Usual price on this route'), findsOneWidget);
    expect(find.textContaining('30 trips'), findsOneWidget);
    await tester.pumpWidget(app(RateRangeLine(key: UniqueKey(), pickup: 'Mumbai', drop: 'Jaipur', vehicleType: '14ft', source: r(null))));
    await tester.pump();
    expect(find.byKey(const ValueKey('rateRangeLine')), findsNothing);
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.rateRange: false});
    await tester.pumpWidget(app(RateRangeLine(key: UniqueKey(), pickup: 'Mumbai', drop: 'Jaipur', vehicleType: '14ft', source: r(const RateRange(1, 2, 3, 5)))));
    await tester.pump();
    expect(find.byKey(const ValueKey('rateRangeLine')), findsNothing);
  });
}
