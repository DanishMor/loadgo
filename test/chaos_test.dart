import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/errors/friendly_error.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/offer.dart';
import 'package:transport_app/core/network/with_retry.dart';
import 'package:transport_app/core/pricing/fare_calculator.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/offer_service.dart';
import 'package:transport_app/core/services/server_clock.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/core/models/vehicle.dart';

FirebaseException fe(String code) => FirebaseException(plugin: 'firestore', code: code);

/// Part 5 (H19, H22): the network and the server misbehave in the middle of a flow.
void main() {
  group('retry with backoff and jitter', () {
    test('the pauses are spread by +-25% and are not the same for every phone', () async {
      final sleeps = <Duration>[];
      Future<void> sleep(Duration d) async => sleeps.add(d);
      final seen = <int>{};
      for (var seed = 0; seed < 20; seed++) {
        sleeps.clear();
        var calls = 0;
        await withRetry(() async {
          if (++calls < 3) throw fe('unavailable');
          return 1;
        }, sleep: sleep, random: Random(seed));
        expect(sleeps[0].inMilliseconds, inInclusiveRange(300, 500));
        expect(sleeps[1].inMilliseconds, inInclusiveRange(600, 1000));
        seen.add(sleeps[0].inMilliseconds);
      }
      expect(seen.length, greaterThan(5), reason: 'all phones would ask again at the same moment');
    });

    test('jitter: 0 gives the exact pauses', () async {
      final sleeps = <Duration>[];
      var calls = 0;
      await withRetry(() async {
        if (++calls < 3) throw fe('unavailable');
        return 1;
      }, sleep: (d) async => sleeps.add(d), jitter: 0);
      expect(sleeps, [const Duration(milliseconds: 400), const Duration(milliseconds: 800)]);
    });

    test('the connection flaps: down, up, down, up still ends with the answer', () async {
      var calls = 0;
      final r = await withRetry(() async {
        calls++;
        if (calls == 1 || calls == 3) throw fe('unavailable');
        if (calls == 2) throw fe('deadline-exceeded');
        return 'done';
      }, attempts: 5, sleep: (_) async {}, jitter: 0);
      expect((r, calls), ('done', 4));
    });

    test('permission-denied in the middle of the flow stops at once, with the sentence for it', () async {
      var calls = 0;
      Object? caught;
      try {
        await withRetry(() async {
          calls++;
          if (calls == 2) throw fe('permission-denied');
          throw fe('unavailable');
        }, attempts: 5, sleep: (_) async {}, jitter: 0);
      } catch (e) {
        caught = e;
      }
      expect(calls, 2);
      expect(FriendlyError.of(caught), 'errorNoAccess');
    });

    test('a call that never answers is given up after its timeout and does not hang the flow', () async {
      final started = DateTime.now();
      await expectLater(
        withRetry(() => Completer<int>().future, attempts: 2, timeout: const Duration(milliseconds: 30), sleep: (_) async {}, jitter: 0),
        throwsA(isA<TimeoutException>()),
      );
      expect(DateTime.now().difference(started).inSeconds, lessThan(3));
    });
  });

  group('clock skew', () {
    tearDown(() {
      ServerClock.deviceNow = DateTime.now;
      ServerClock.observe(DateTime.now(), receivedAt: DateTime.now());
    });

    test('a phone that is 3 hours fast still counts server time', () {
      final server = DateTime.utc(2026, 10, 19, 12);
      ServerClock.deviceNow = () => server.add(const Duration(hours: 3));
      ServerClock.observe(server);
      expect(ServerClock.now().difference(server).abs(), lessThan(const Duration(seconds: 1)));
    });

    test('a phone that is 2 days slow still counts server time', () {
      final server = DateTime.utc(2026, 10, 19, 12);
      ServerClock.deviceNow = () => server.subtract(const Duration(days: 2));
      ServerClock.observe(server);
      expect(ServerClock.now().difference(server).abs(), lessThan(const Duration(seconds: 1)));
    });
  });

  group('double taps and parallel calls on the real services (fake Firestore)', () {
    late FakeFirebaseFirestore db;
    String? uid;
    late Load load;
    late Vehicle vehicle;

    setUp(() async {
      db = FakeFirebaseFirestore();
      Backend.useFakes(db: db, uid: () => uid);
      uid = 'cust1';
      await db.collection('users').doc('cust1').set({'role': 'customer'});
      final id = await LoadService.post(
        pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: null,
        pickupDate: DateTime.now().add(const Duration(days: 2)), notes: '',
      );
      load = Load.fromDoc(await db.collection('loads').doc(id).get());
      uid = 'drv1';
      await db.collection('users').doc('drv1').set({'role': 'driver', 'driverName': 'Ramesh'});
      final vid = await VehicleService.add(number: 'MH12AB1234', type: '14ft', capacity: 4, rcNumber: 'RC1');
      vehicle = Vehicle.fromDoc(await db.collection('vehicles').doc(vid).get());
    });

    test('two taps on Send bid at the same moment end as ONE bid document (its id is fixed: load + driver)', () async {
      // Fake Firestore does not overlap transactions, so both calls may report success here. In the real database the
      // second create is an update, which the rules refuse (rules test: one bid per driver per load).
      final results = await Future.wait([
        OfferService.send(load: load, vehicle: vehicle, pricePaise: 2500000).then<Object>((v) => v, onError: (Object e) => e),
        OfferService.send(load: load, vehicle: vehicle, pricePaise: 2500000).then<Object>((v) => v, onError: (Object e) => e),
      ]);
      expect(results.whereType<Exception>().every((e) => e is OfferExistsException), isTrue);
      expect(results.whereType<String>(), everyElement('${load.id}_drv1'));
      expect((await db.collection('offers').get()).docs.length, 1);
    });

    test('two taps on Post load do not corrupt anything: two loads, each complete', () async {
      uid = 'cust1';
      final ids = await Future.wait([
        LoadService.post(pickup: 'A', drop: 'B', cargoType: 'FMCG', weight: 1, vehicleType: '14ft', budget: null, pickupDate: DateTime.now().add(const Duration(days: 2)), notes: ''),
        LoadService.post(pickup: 'A', drop: 'B', cargoType: 'FMCG', weight: 1, vehicleType: '14ft', budget: null, pickupDate: DateTime.now().add(const Duration(days: 2)), notes: ''),
      ]);
      expect(ids.toSet().length, 2);
      for (final id in ids) {
        expect(Load.fromDoc(await db.collection('loads').doc(id).get()).status, 'open');
      }
    });

    test('fare maths is integer paise and never negative, whatever the distance', () {
      for (final km in [0, 1, 5, 100, 5000, 100000]) {
        final f = FareCalculator.calculate(rule: const PricingRule(baseFare: 50000, perKm: 2800, minimumFare: 80000), distanceKm: km, platformFeePercent: 5, gstPercent: 5);
        expect(f.total, isNonNegative);
        expect(f.total, f.tripFare + f.platformFee + f.gst);
      }
    });
  });
}
