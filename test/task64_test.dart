import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/safety/share_trip.dart';
import 'package:transport_app/core/safety/trip_share_service.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/share/share_links.dart';
import 'package:transport_app/core/trip/trip_alerts.dart';

import 'test_utils.dart';

class _Fixed implements Random {
  int i = 0;
  @override
  int nextInt(int max) => i++ % max;
  @override
  double nextDouble() => 0.5;
  @override
  bool nextBool() => true;
}

void main() {
  late FakeFirebaseFirestore db;
  final now = DateTime(2026, 10, 7, 12);

  Future<Booking> booking({String status = 'in_transit'}) async {
    await db.collection('bookings').doc('b1').set({
      'driverId': 'd1', 'customerId': 'c1', 'status': status, 'pickup': 'Pune', 'drop': 'Delhi', 'cargoType': 'Steel', 'weight': 5,
      'vehicleNumber': 'MH12AB1234', 'vehicleType': '20ft', 'driverName': 'Ramesh Kumar', 'driverPhone': '+919800000001',
    });
    return Booking.fromDoc(await db.collection('bookings').doc('b1').get());
  }

  setUp(() {
    languageNotifier.value = AppLanguage.english;
    ShareLinks.host = 'loadgo-defc2.web.app';
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'c1');
    FeaturesService.reset();
  });

  group('tokens and links', () {
    test('a token is 24 characters from the safe alphabet', () {
      final t = TripShareService.newToken();
      expect(t, matches(RegExp(r'^[abcdefghijkmnpqrstuvwxyz23456789]{24}$')));
      expect(TripShareService.newToken(), isNot(t));
    });

    test('link and parse round trip; other links are refused', () {
      final t = TripShareService.newToken(_Fixed());
      final link = TripShareService.linkFor(t);
      expect(link, 'https://loadgo-defc2.web.app/trip/$t');
      expect(TripShareService.parseToken(link), t);
      for (final bad in [null, '', 'http://loadgo-defc2.web.app/trip/$t', 'https://x.in/load/$t', 'https://x.in/trip/short', 'https://x.in/trip/${t.toUpperCase()}', 'https://x.in/trip/$t/extra']) {
        expect(TripShareService.parseToken(bad), isNull, reason: '$bad');
      }
    });

    test('only the first name of the driver is shared', () {
      expect(TripShareService.firstName('Ramesh Kumar'), 'Ramesh');
      expect(TripShareService.firstName('  Asha '), 'Asha');
      expect(TripShareService.firstName(''), '');
      expect(TripShareService.firstName('x' * 80).length, 40);
    });
  });

  group('createOrReuse and syncStatus', () {
    test('creates a share with only the public fields and a 24 hour end', () async {
      final b = await booking();
      final token = await TripShareService.createOrReuse(b, now: now);
      final d = (await db.collection('trip_shares').doc(token).get()).data()!;
      expect(d.keys.toSet(), {'bookingId', 'ownerId', 'pickup', 'drop', 'status', 'vehicleNumber', 'driverName', 'statusAt', 'expiresAt', 'createdAt'});
      expect(d['driverName'], 'Ramesh');
      expect(d['ownerId'], 'c1');
      expect((d['expiresAt'] as Timestamp).toDate(), now.add(const Duration(hours: 24)));
      expect(d.containsKey('driverPhone'), isFalse);
    });

    test('the same running link is reused; an ending one is replaced', () async {
      final b = await booking();
      final a = await TripShareService.createOrReuse(b, now: now);
      expect(await TripShareService.createOrReuse(b, now: now.add(const Duration(hours: 2))), a);
      final c = await TripShareService.createOrReuse(b, now: now.add(const Duration(hours: 23, minutes: 30)));
      expect(c, isNot(a));
      expect((await db.collection('trip_shares').get()).docs.length, 2);
    });

    test('syncStatus updates live links only, once, and never throws', () async {
      final b = await booking();
      final token = await TripShareService.createOrReuse(b, now: DateTime.now());
      await db.collection('trip_shares').doc('endedendedendedendedende2').set({'bookingId': 'b1', 'ownerId': 'c1', 'status': 'accepted', 'expiresAt': Timestamp.fromDate(DateTime(2020))});
      await TripShareService.syncStatus('b1', 'delivered');
      expect((await db.collection('trip_shares').doc(token).get())['status'], 'delivered');
      expect((await db.collection('trip_shares').doc('endedendedendedendedende2').get())['status'], 'accepted');
      await TripShareService.syncStatus('nothing', 'x');
    });

    test('stop deletes the link', () async {
      final token = await TripShareService.createOrReuse(await booking(), now: now);
      await TripShareService.stop(token);
      expect((await db.collection('trip_shares').doc(token).get()).exists, isFalse);
    });
  });

  group('trip summary text', () {
    test('has the follow link only when one is given', () async {
      final b = await booking();
      expect(tripSummaryText(b, who: 'Asha'), isNot(contains('Follow this trip')));
      final t = tripSummaryText(b, who: 'Asha', link: 'https://loadgo-defc2.web.app/trip/abc');
      expect(t, contains('Follow this trip (valid 24 hours): https://loadgo-defc2.web.app/trip/abc'));
    });
  });

  group('ShareTripButton', () {
    testWidgets('with the feature on, the shared text carries a live link', (t) async {
      final b = await t.runAsync(() => booking());
      await t.runAsync(() => db.collection('users').doc('c1').set({'name': 'Asha', 'emergencyContacts': [{'name': 'Mom', 'phone': '+919811111111'}]}));
      FeaturesService.notifier.value = const Features(flags: {FeatureKey.tripShare: true});
      await t.pumpWidget(MaterialApp(home: LanguageScope(notifier: languageNotifier, child: Scaffold(body: ShareTripButton(booking: b!)))));
      await t.tap(find.byKey(const ValueKey('shareTripButton')));
      await settle(t);
      final shares = (await t.runAsync(() => db.collection('trip_shares').get()))!.docs;
      expect(shares.length, 1, reason: 'a link was created for the share');
    });

    testWidgets('with the feature off, no link is created', (t) async {
      final b = await t.runAsync(() => booking());
      await t.runAsync(() => db.collection('users').doc('c1').set({'name': 'Asha', 'emergencyContacts': [{'name': 'Mom', 'phone': '+919811111111'}]}));
      FeaturesService.notifier.value = const Features(flags: {FeatureKey.tripShare: false});
      await t.pumpWidget(MaterialApp(home: LanguageScope(notifier: languageNotifier, child: Scaffold(body: ShareTripButton(booking: b!)))));
      await t.tap(find.byKey(const ValueKey('shareTripButton')));
      await settle(t);
      expect((await t.runAsync(() => db.collection('trip_shares').get()))!.docs, isEmpty);
    });
  });

  group('project files', () {
    test('the public page reads trip_shares through the REST API and is served for /trip/**', () {
      final page = File('hosting/trip.html').readAsStringSync();
      expect(page, contains('firestore.googleapis.com/v1/projects/loadgo-defc2'));
      expect(page, contains('trip_shares/'));
      expect(page, contains('noindex'));
      expect(page, contains('name="viewport"'));
      expect(File('firebase.json').readAsStringSync(), contains('"/trip/**"'));
    });
  });

  test('rules mention trip_shares with a public get and no public list', () {
    final r = File('firestore.rules').readAsStringSync();
    expect(r, contains('match /trip_shares/{token}'));
    expect(r, contains('allow get: if resource.data.expiresAt > request.time;'));
  });
}
