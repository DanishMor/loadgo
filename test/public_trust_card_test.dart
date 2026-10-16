import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/trust/public_trust.dart';
import 'package:transport_app/core/trust/public_trust_card.dart';

void main() {
  late FakeFirebaseFirestore db;

  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'c1');
    languageNotifier.value = AppLanguage.english;
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.tripTrustCard: true});
  });
  tearDown(FeaturesService.reset);

  Widget app(Widget child) => MaterialApp(theme: AppTheme.build(Brightness.light), home: Scaffold(body: child));

  testWidgets('shows verified, rating, trips and the month the driver joined', (tester) async {
    await tester.pumpWidget(app(PublicTrustCard(
      driverId: 'd1',
      source: Stream.value(const PublicTrust(uid: 'd1', trips: 42, rating: 4.6, ratingCount: 30, verified: true, since: '2026-03')),
    )));
    await tester.pump();
    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('4.6 stars (30)'), findsOneWidget);
    expect(find.text('42 trips done'), findsOneWidget);
    expect(find.text('Since Mar 2026'), findsOneWidget);
  });

  testWidgets('one trip reads "1 trip done"; a driver with nothing yet is "New on Load 20"', (tester) async {
    await tester.pumpWidget(app(PublicTrustCard(driverId: 'd1', source: Stream.value(const PublicTrust(uid: 'd1', trips: 1)))));
    await tester.pump();
    expect(find.text('1 trip done'), findsOneWidget);
    await tester.pumpWidget(app(PublicTrustCard(key: UniqueKey(), driverId: 'd1', source: Stream.value(const PublicTrust(uid: 'd1')))));
    await tester.pump();
    expect(find.text('New on Load 20'), findsOneWidget);
  });

  testWidgets('no summary, a failed read, no driver or the switch off: nothing is drawn', (tester) async {
    await tester.pumpWidget(app(PublicTrustCard(driverId: 'd1', source: Stream.value(null))));
    await tester.pump();
    expect(find.byKey(const ValueKey('publicTrustCard')), findsNothing);
    await tester.pumpWidget(app(PublicTrustCard(key: UniqueKey(), driverId: 'd1', source: Stream.error(StateError('denied')))));
    await tester.pump();
    expect(find.byKey(const ValueKey('publicTrustCard')), findsNothing);
    await tester.pumpWidget(app(const PublicTrustCard(driverId: '')));
    expect(find.byKey(const ValueKey('publicTrustCard')), findsNothing);
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.tripTrustCard: false});
    await tester.pumpWidget(app(PublicTrustCard(key: UniqueKey(), driverId: 'd1', source: Stream.value(const PublicTrust(uid: 'd1', trips: 5)))));
    await tester.pump();
    expect(find.byKey(const ValueKey('publicTrustCard')), findsNothing);
  });

  testWidgets('end to end: reads the server-written summary from public_trust by the driver id', (tester) async {
    await db.collection('public_trust').doc('d9').set({'trips': 7, 'rating': 4.0, 'ratingCount': 3, 'verified': true, 'since': '2026-01'});
    await tester.pumpWidget(app(const PublicTrustCard(driverId: 'd9')));
    await tester.pumpAndSettle();
    expect(find.text('7 trips done'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
  });

  testWidgets('big text and a narrow screen wrap instead of overflowing', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(360, 640), textScaler: TextScaler.linear(2.0)),
      child: app(PublicTrustCard(
        driverId: 'd1',
        source: Stream.value(const PublicTrust(uid: 'd1', trips: 1234, rating: 4.8, ratingCount: 999, verified: true, since: '2024-11')),
      )),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
