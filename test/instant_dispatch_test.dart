import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/dispatch/dispatch_config_service.dart';
import 'package:transport_app/core/dispatch/dispatch_models.dart';
import 'package:transport_app/core/dispatch/instant_progress.dart';
import 'package:transport_app/core/dispatch/load_dispatch_service.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/server_clock.dart';
import 'package:transport_app/core/services/vehicle_service.dart';

/// U12: instant mode: the search in waves, price raise, wider range, first valid accept wins.
void main() {
  final t0 = DateTime(2030, 1, 1, 12);
  const cfg = DispatchConfig.defaults;
  InstantProgress at(int seconds, {int boost = 0}) => InstantProgress.at(cfg, createdAt: t0, now: t0.add(Duration(seconds: seconds)), boost: boost);

  group('InstantProgress', () {
    test('wave 1 at once, wave 2 at 30 s, wave 3 at 60 s, then stalled after the accept time', () {
      expect((at(0).wave, at(0).reachKm, at(0).secondsLeft), (0, 3, 30));
      expect((at(29).wave, at(29).secondsLeft), (0, 1));
      expect((at(30).wave, at(30).reachKm, at(30).secondsLeft), (1, 7, 30));
      expect((at(60).wave, at(60).reachKm, at(60).secondsLeft, at(60).inLastWave), (2, 15, 30, true));
      expect(at(89).stalled, isFalse);
      expect((at(90).stalled, at(90).secondsLeft), (true, 0));
      expect(at(100000).stalled, isTrue);
    });

    test('the ring length is the stage length; a clock slightly before the post counts as the start', () {
      expect(at(0).stageSeconds, 30);
      expect(at(60).stageSeconds, 30);
      expect(at(-5).wave, 0);
    });

    test('widening shows the longer reach in the same wave', () {
      expect(at(0, boost: 1).reachKm, 7);
      expect(at(0, boost: 3).reachKm, 15);
      expect(at(30, boost: 1).reachKm, 15);
    });

    test('another configuration is used (a 45 second accept time)', () {
      final c = DispatchConfig.fromMap({'acceptSeconds': 45});
      expect(InstantProgress.at(c, createdAt: t0, now: t0.add(const Duration(seconds: 100))).stalled, isFalse);
      expect(InstantProgress.at(c, createdAt: t0, now: t0.add(const Duration(seconds: 105))).stalled, isTrue);
    });
  });

  group('PriceBump', () {
    test('plus 5 or 10 percent in whole rupees, rounded up', () {
      expect(PriceBump.bumped(25000, 5), 26250);
      expect(PriceBump.bumped(25000, 10), 27500);
      expect(PriceBump.bumped(999, 5), 1049);
      expect(PriceBump.bumped(24999.5, 5), 26250);
      expect(PriceBump.bumped(1, 5), 2, reason: 'always at least one rupee more');
    });

    test('refused for no price, other percents, over 300 percent of the estimate, over the ceiling', () {
      expect(PriceBump.bumped(null, 5), isNull);
      expect(PriceBump.bumped(0, 5), isNull);
      expect(PriceBump.bumped(-3, 5), isNull);
      expect(PriceBump.bumped(100, 7), isNull);
      expect(PriceBump.bumped(299, 10, estimatePaise: 10000), isNull, reason: '100 rupees estimate, 300 rupees limit: 329 is over');
      expect(PriceBump.bumped(250, 10, estimatePaise: 10000), 275);
      expect(PriceBump.bumped(PriceBump.ceilingRupees, 5), isNull);
    });
  });

  group('LoadDispatchService and the accept race', () {
    late FakeFirebaseFirestore db;
    String? uid;

    setUp(() {
      db = FakeFirebaseFirestore();
      uid = 'customer1';
      Backend.useFakes(db: db, uid: () => uid);
      DispatchConfigService.reset();
      ServerClock.reset();
    });

    Future<String> post({LoadMode mode = LoadMode.instant, AutoAccept? auto}) => LoadService.post(
          pickup: 'Delhi',
          drop: 'Mumbai',
          cargoType: 'FMCG',
          weight: 8,
          vehicleType: '20ft',
          budget: 25000,
          pickupDate: DateTime(2026, 10, 5),
          notes: '',
          mode: mode,
          autoAccept: auto,
        );

    Future<Load> read(String id) async => Load.fromDoc(await db.collection('loads').doc(id).get());

    test('an instant load writes no mode (old behaviour); a bid load writes its mode, window and rule', () async {
      final a = await post();
      expect((await db.collection('loads').doc(a).get()).data()!.containsKey('mode'), isFalse);
      final b = await post(mode: LoadMode.bid, auto: const AutoAccept(maxPaise: 2500000, minRating: 4));
      final d = (await db.collection('loads').doc(b).get()).data()!;
      expect(d['mode'], 'bid');
      expect((d['bidWindowEnds'] as Timestamp).toDate().isAfter(DateTime.now().add(const Duration(minutes: 9))), isTrue);
      expect(d['autoAccept'], {'maxPaise': 2500000, 'minRating': 4.0, 'verifiedOnly': false});
      final l = await read(b);
      expect((l.mode, l.autoAccept!.maxPaise), (LoadMode.bid, 2500000));
      await expectLater(LoadService.post(pickup: 'Delhi', drop: 'Mumbai', cargoType: 'FMCG', weight: 8, vehicleType: '20ft', budget: 1, pickupDate: DateTime(2026, 10, 5), notes: '', mode: LoadMode.scheduled), throwsArgumentError);
    });

    test('raise the price by 5 percent, then widen the range up to three times; others cannot', () async {
      final id = await post();
      expect(await LoadDispatchService.raisePrice(await read(id), 5), 26250);
      expect((await read(id)).budget, 26250);
      expect(await LoadDispatchService.raisePrice(await read(id), 10), 28875);
      expect(await LoadDispatchService.widenRange(await read(id)), 1);
      expect(await LoadDispatchService.widenRange(await read(id)), 2);
      expect(await LoadDispatchService.widenRange(await read(id)), 3);
      expect(await LoadDispatchService.widenRange(await read(id)), isNull);
      expect((await read(id)).ringBoost, 3);
      uid = 'driver1';
      expect(await LoadDispatchService.raisePrice(await read(id), 5), isNull);
      expect(await LoadDispatchService.widenRange(await read(id)), isNull);
    });

    test('a bid window is extended from its old end, never into the past, and only for the owner of a bid load', () async {
      final id = await post(mode: LoadMode.bid);
      final before = (await read(id)).bidWindowEnds!;
      final end = await LoadDispatchService.extendBidWindow(await read(id), minutes: 10);
      expect(end!.difference(before).inMinutes, 10);
      expect(await LoadDispatchService.extendBidWindow(await read(id), minutes: 0), isNull);
      final inst = await post();
      expect(await LoadDispatchService.extendBidWindow(await read(inst)), isNull);
      uid = 'driver1';
      expect(await LoadDispatchService.extendBidWindow(await read(id)), isNull);
    });

    test('the auto-accept rule is saved and cleared', () async {
      final id = await post(mode: LoadMode.bid);
      await LoadDispatchService.setAutoAccept(await read(id), const AutoAccept(maxPaise: 90000, verifiedOnly: true));
      expect((await read(id)).autoAccept!.verifiedOnly, isTrue);
      await LoadDispatchService.setAutoAccept(await read(id), null);
      expect((await read(id)).autoAccept, isNull);
    });

    Future<Vehicle> vehicleOf(String driver, String number) async {
      uid = driver;
      await db.collection('users').doc(driver).set({'driverName': 'Ramesh', 'phone': '+919800000000'});
      await VehicleService.add(number: number, type: '20ft', capacity: 10, rcNumber: 'RC1');
      return (await VehicleService.fetchMyActive()).single;
    }

    test('the first accept wins; the second driver is told the load is gone and no second booking exists', () async {
      // Fake Firestore does not serialise overlapping transactions, so this checks the second arrival; the real
      // race (two commits at the same moment) is decided by Firestore and is covered by the rules test U15.
      final id = await post();
      final v1 = await vehicleOf('driver1', 'MH12AB1234');
      final v2 = await vehicleOf('driver2', 'KA01CD5678');
      uid = 'driver1';
      await BookingService.accept(loadId: id, vehicle: v1);
      uid = 'driver2';
      await expectLater(BookingService.accept(loadId: id, vehicle: v2), throwsA(isA<LoadUnavailableException>()));
      expect((await db.collection('bookings').get()).docs.length, 1);
      expect((await read(id)).status, LoadStatus.matched);
    });

    test('a bid-mode load cannot be taken by a direct accept', () async {
      final id = await post(mode: LoadMode.bid);
      final v1 = await vehicleOf('driver1', 'MH12AB1234');
      uid = 'driver1';
      await expectLater(BookingService.accept(loadId: id, vehicle: v1), throwsA(isA<LoadUnavailableException>()));
      expect((await db.collection('bookings').get()).docs, isEmpty);
    });
  });
}
