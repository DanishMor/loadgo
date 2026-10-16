import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/services/location_service.dart';
import 'package:transport_app/core/services/safety_service.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/driver/safety_checkin_card.dart';
import 'package:transport_app/driver/trip_geofence_banner.dart';

void main() {
  late FakeFirebaseFirestore db;
  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'd1');
    languageNotifier.value = AppLanguage.english;
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.safetyCheckin: true});
  });
  tearDown(FeaturesService.reset);

  Widget app(Widget child) => MaterialApp(theme: AppTheme.build(Brightness.light), home: Scaffold(body: SingleChildScrollView(child: child)));

  testWidgets('"I am OK" thanks the driver and sends nothing', (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(app(SafetyCheckinCard(send: (b, r) async => sent.add(r))));
    expect(find.text('Your truck has been standing for a long time. Are you OK?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('checkinOkButton')));
    await tester.pump();
    expect(find.byKey(const ValueKey('checkinOk')), findsOneWidget);
    await tester.pump(const Duration(minutes: 11));
    expect(sent, isEmpty, reason: 'the timer was stopped by the answer');
  });

  testWidgets('"I need help" sends one alert with the reason checkin_help and says what happens next', (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(app(SafetyCheckinCard(send: (b, r) async => sent.add(r))));
    await tester.tap(find.byKey(const ValueKey('checkinHelpButton')));
    await tester.pump();
    expect(sent, ['checkin_help']);
    expect(find.textContaining('Help is being asked for'), findsOneWidget);
    expect(find.byKey(const ValueKey('checkinHelpButton')), findsNothing, reason: 'no second press');
    await tester.pump(const Duration(minutes: 11));
    expect(sent, ['checkin_help'], reason: 'no extra alert from the timer');
  });

  testWidgets('no answer for the window sends checkin_no_answer once', (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(app(SafetyCheckinCard(window: const Duration(minutes: 10), send: (b, r) async => sent.add(r))));
    await tester.pump(const Duration(minutes: 9));
    expect(sent, isEmpty);
    await tester.pump(const Duration(minutes: 2));
    expect(sent, ['checkin_no_answer']);
    expect(find.textContaining('No answer, so support has been told'), findsOneWidget);
  });

  testWidgets('an alert that cannot be written says so, so the driver calls', (tester) async {
    await tester.pumpWidget(app(SafetyCheckinCard(send: (b, r) async => throw StateError('offline'))));
    await tester.tap(find.byKey(const ValueKey('checkinHelpButton')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('checkinNotSent')), findsOneWidget);
  });

  test('the SOS carries the reason; a plain SOS has no reason field and an odd reason becomes a plain SOS', () async {
    final a = await SafetyService.sendSos(reason: 'checkin_no_answer');
    final b = await SafetyService.sendSos();
    final c = await SafetyService.sendSos(reason: 'something else');
    expect((await db.collection('sos_alerts').doc(a).get()).data()!['reason'], 'checkin_no_answer');
    expect((await db.collection('sos_alerts').doc(b).get()).data()!.containsKey('reason'), isFalse);
    expect((await db.collection('sos_alerts').doc(c).get()).data()!.containsKey('reason'), isFalse);
  });

  testWidgets('end to end: a 30 minute halt in the banner shows the check-in; with the switch off the old halt card stays', (tester) async {
    final positions = StreamController<Coordinates>.broadcast();
    addTearDown(positions.close);
    var now = DateTime(2026, 10, 17, 12);
    Widget banner() => app(TripGeofenceBanner(key: UniqueKey(), dropPlace: 'Mumbai', positions: positions.stream, now: () => now));
    await tester.pumpWidget(banner());
    await tester.pump();
    positions.add((lat: 26.9, lng: 75.8)); // Jaipur area, far from Mumbai
    await tester.pump();
    now = now.add(const Duration(minutes: 31));
    positions.add((lat: 26.9001, lng: 75.8001));
    await tester.pump();
    expect(find.byKey(const ValueKey('safetyCheckin')), findsOneWidget);
    expect(find.byKey(const ValueKey('geoHalt')), findsNothing);

    FeaturesService.notifier.value = const Features(flags: {FeatureKey.safetyCheckin: false});
    now = DateTime(2026, 10, 17, 14);
    await tester.pumpWidget(banner());
    await tester.pump();
    positions.add((lat: 26.9, lng: 75.8));
    await tester.pump();
    now = now.add(const Duration(minutes: 31));
    positions.add((lat: 26.9001, lng: 75.8001));
    await tester.pump();
    expect(find.byKey(const ValueKey('geoHalt')), findsOneWidget);
    expect(find.byKey(const ValueKey('safetyCheckin')), findsNothing);
  });
}
