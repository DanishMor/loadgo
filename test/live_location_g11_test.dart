import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/location/live_location_policy.dart';
import 'package:transport_app/core/location/live_location_sharer.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/services/location_service.dart';
import 'package:transport_app/core/widgets/location_widgets.dart';

Booking _booking(String status) => Booking.fromMap('b1', {
      'customerId': 'c1', 'driverId': 'd1', 'status': status, 'pickup': 'Delhi', 'drop': 'Jaipur', 'loadId': 'l', 'vehicleId': 'v',
      'cargoType': 'FMCG', 'weight': 2, 'vehicleType': '14ft', 'notes': '', 'vehicleNumber': 'N', 'driverName': 'D', 'driverPhone': '1',
      'timeline': <String, Object?>{},
    });

void main() {
  final t0 = DateTime(2026, 10, 16, 12);
  const delhi = (lat: 28.6139, lng: 77.2090);

  group('policy', () {
    test('first fix is written; then a gap and a move are both needed', () {
      final p = LiveLocationPolicy();
      expect(p.shouldWrite(delhi, t0), isTrue);
      p.wrote(delhi, t0);
      final moved = (lat: 28.6139 + 0.002, lng: 77.2090); // about 220 m
      expect(p.shouldWrite(moved, t0.add(const Duration(seconds: 10))), isFalse, reason: 'too soon');
      expect(p.shouldWrite(delhi, t0.add(const Duration(seconds: 60))), isFalse, reason: 'did not move');
      expect(p.shouldWrite((lat: 28.6139 + 0.0003, lng: 77.2090), t0.add(const Duration(seconds: 60))), isFalse, reason: 'only 33 m');
      expect(p.shouldWrite(moved, t0.add(const Duration(seconds: 60))), isTrue);
    });

    test('a parked truck still shows a heartbeat every 5 minutes', () {
      final p = LiveLocationPolicy()..wrote(delhi, t0);
      expect(p.shouldWrite(delhi, t0.add(const Duration(minutes: 4))), isFalse);
      expect(p.shouldWrite(delhi, t0.add(const Duration(minutes: 5))), isTrue);
    });

    test('config values are bounded; junk gives the defaults', () {
      final c = LiveLocationConfig.fromMap({'minGapSeconds': 1, 'minMoveMeters': 'a', 'heartbeatSeconds': 99999});
      expect(c.minGap, const Duration(seconds: 30));
      expect(c.minMoveMeters, 100);
      expect(c.heartbeat, const Duration(minutes: 5));
      final ok = LiveLocationConfig.fromMap({'minGapSeconds': 60, 'minMoveMeters': 250, 'heartbeatSeconds': 600});
      expect((ok.minGap.inSeconds, ok.minMoveMeters, ok.heartbeat.inSeconds), (60, 250, 600));
      expect(LiveLocationConfig.fromMap(null).minGap, const Duration(seconds: 30));
    });
  });

  group('sharer', () {
    late StreamController<Coordinates> positions;
    late StreamController<Booking?> trip;
    late List<(String, double, double)> written;
    var clock = DateTime(2026, 10, 16, 12);
    var consent = true;

    setUp(() async {
      await LiveLocationSharer.stop();
      positions = StreamController<Coordinates>.broadcast();
      trip = StreamController<Booking?>.broadcast();
      written = [];
      clock = t0;
      consent = true;
      LocationService.useFake(() => positions.stream);
      LiveLocationSharer.now = () => clock;
      LiveLocationSharer.consentGiven = () async => consent;
      LiveLocationSharer.watchBooking = (_) => trip.stream;
      LiveLocationSharer.write = (id, lat, lng) async => written.add((id, lat, lng));
      FeaturesService.notifier.value = const Features(flags: {FeatureKey.liveLocation: true});
    });
    tearDown(() async {
      await LiveLocationSharer.stop();
      LocationService.useFake(null);
      FeaturesService.reset();
      await positions.close();
      await trip.close();
    });

    Future<void> pump() => Future<void>.delayed(Duration.zero);

    test('switch off: nothing starts', () async {
      FeaturesService.notifier.value = const Features(flags: {FeatureKey.liveLocation: false});
      expect(await LiveLocationSharer.start('b1'), SharingState.off);
      positions.add(delhi);
      await pump();
      expect(written, isEmpty);
    });

    test('no consent: nothing is written and the reason is given', () async {
      consent = false;
      expect(await LiveLocationSharer.start('b1'), SharingState.noConsent);
      positions.add(delhi);
      await pump();
      expect(written, isEmpty);
      expect(LiveLocationSharer.activeBooking, isNull);
    });

    test('with consent: writes follow the policy', () async {
      expect(await LiveLocationSharer.start('b1'), SharingState.on);
      positions.add(delhi);
      await pump();
      positions.add((lat: 28.7, lng: 77.3)); // same instant: ignored
      await pump();
      clock = t0.add(const Duration(seconds: 45));
      positions.add((lat: 28.7, lng: 77.3));
      await pump();
      expect(written, [('b1', 28.6139, 77.209), ('b1', 28.7, 77.3)]);
    });

    test('starting again for the same trip keeps one stream; another trip replaces it', () async {
      await LiveLocationSharer.start('b1');
      await LiveLocationSharer.start('b1');
      positions.add(delhi);
      await pump();
      expect(written.length, 1);
      await LiveLocationSharer.start('b2');
      clock = t0.add(const Duration(minutes: 1));
      positions.add((lat: 29, lng: 78));
      await pump();
      expect(written.last.$1, 'b2');
    });

    test('it stops by itself when the trip is delivered or cancelled', () async {
      await LiveLocationSharer.start('b1');
      trip.add(_booking('in_transit'));
      await pump();
      expect(LiveLocationSharer.state.value, SharingState.on);
      trip.add(_booking('delivered'));
      await pump();
      await pump();
      expect(LiveLocationSharer.state.value, SharingState.off);
      positions.add(delhi);
      await pump();
      expect(written, isEmpty);
    });

    test('a failed write never throws and the next fix tries again', () async {
      var fail = true;
      LiveLocationSharer.write = (id, lat, lng) async {
        if (fail) throw StateError('offline');
        written.add((id, lat, lng));
      };
      await LiveLocationSharer.start('b1');
      positions.add(delhi);
      await pump();
      fail = false;
      clock = t0.add(const Duration(minutes: 6));
      positions.add(delhi);
      await pump();
      expect(written.length, 1);
    });
  });

  testWidgets('last seen reads in minutes, hours and now', (tester) async {
    languageNotifier.value = AppLanguage.english;
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    final now = DateTime(2026, 10, 16, 12);
    expect(lastSeenText(ctx, now.subtract(const Duration(seconds: 20)), now: now), 'Last seen just now');
    expect(lastSeenText(ctx, now.subtract(const Duration(minutes: 7)), now: now), 'Last seen 7 min ago');
    expect(lastSeenText(ctx, now.subtract(const Duration(hours: 5)), now: now), 'Last seen 5 h ago');
  });
}
