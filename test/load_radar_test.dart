import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/dispatch/dispatch_models.dart';
import 'package:transport_app/core/dispatch/load_radar.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/vehicle.dart';

/// U16: the incoming-load contract: unlocked, matching, open, not expired, one at a time.
void main() {
  final t0 = DateTime(2030, 1, 1, 12);
  const cfg = DispatchConfig.defaults;
  const near = (lat: 28.6239, lng: 77.2090); // about 2 km
  const mid = (lat: 28.6539, lng: 77.2090); // about 5.6 km

  Vehicle truck({String type = '14ft', num capacity = 6, String number = 'DL01AB1234'}) => Vehicle(
        id: number,
        ownerId: 'd1',
        number: number,
        type: type,
        capacity: capacity,
        rcNumber: 'RC',
        status: 'active',
      );

  Load load(String id, {String pickup = 'Delhi', String type = '14ft', num weight = 4, DateTime? created, DateTime? touched, num? budget = 20000, int boost = 0, LoadMode mode = LoadMode.instant, String shipper = 'c1', String status = 'open', List<String> blocked = const [], String? invited}) => Load(
        id: id,
        shipperId: shipper,
        pickup: pickup,
        drop: 'Jaipur',
        cargoType: 'FMCG',
        weight: weight,
        vehicleType: type,
        budget: budget,
        pickupDate: null,
        notes: '',
        status: status,
        createdAt: Timestamp.fromDate(created ?? t0),
        updatedAt: touched == null ? null : Timestamp.fromDate(touched),
        ringBoost: boost,
        mode: mode,
        blockedDriverIds: blocked,
        invitedDriverId: invited,
      );

  RadarState compute(List<Load> loads, {int seconds = 0, List<Vehicle>? vehicles, ({double lat, double lng})? origin = near, bool waves = true, Set<String> skipped = const {}}) => RadarEngine.compute(
        loads: loads,
        vehicles: vehicles ?? [truck()],
        origin: origin,
        now: t0.add(Duration(seconds: seconds)),
        driverId: 'd1',
        config: cfg,
        waves: waves,
        skipped: skipped,
      );

  List<String> ids(RadarState s) => [if (s.current != null) s.current!.load.id, for (final q in s.queue) q.load.id];

  test('a fresh load in the first ring is the card with a 30 second window', () {
    final s = compute([load('a')]);
    expect(ids(s), ['a']);
    expect(s.current!.secondsLeft(t0), 30);
    expect(s.current!.km, lessThanOrEqualTo(3));
  });

  test('a load in the second ring is not a card until 30 s have passed, then it is, for 30 s', () {
    expect(compute([load('a')], origin: mid, seconds: 10).current, isNull);
    expect(ids(compute([load('a')], origin: mid, seconds: 30)), ['a']);
    expect(compute([load('a')], origin: mid, seconds: 30).current!.secondsLeft(t0.add(const Duration(seconds: 30))), 30);
    expect(compute([load('a')], origin: mid, seconds: 60).current, isNull, reason: 'the window closed');
  });

  test('the card closes when its accept window ends (the load stays in the feed, not as a card)', () {
    expect(ids(compute([load('a')], seconds: 29)), ['a']);
    expect(compute([load('a')], seconds: 30).current, isNull);
  });

  test('only open loads that the driver can carry: type, capacity and own load are checked', () {
    expect(compute([load('a', type: '20ft')]).current, isNull);
    expect(compute([load('a', weight: 9)]).current, isNull);
    expect(compute([load('a', shipper: 'd1')]).current, isNull);
    expect(compute([load('a', status: 'matched')]).current, isNull);
    expect(compute([load('a', blocked: ['d1'])]).current, isNull);
    expect(compute([load('a')], vehicles: const []).current, isNull, reason: 'no vehicle at all');
    expect(ids(compute([load('a')], vehicles: null)), ['a'], reason: 'vehicles not loaded yet: do not hide');
  });

  test('advance bookings do not ring; they are browsed', () {
    expect(compute([load('a', mode: LoadMode.scheduled)]).current, isNull);
  });

  test('one card per load even if the load arrives twice, and cards queue by when they opened, then by distance', () {
    final a = load('a', created: t0.subtract(const Duration(seconds: 5)));
    final b = load('b', created: t0.subtract(const Duration(seconds: 10)));
    final c = load('c', created: t0.subtract(const Duration(seconds: 10)), pickup: 'Delhi');
    final s = compute([a, a, b, c]);
    expect(ids(s), ['b', 'c', 'a']);
    expect(s.waiting, 2);
  });

  test('skipping a card moves to the next one; a raised price is a new question and comes back', () {
    final a = load('a', created: t0.subtract(const Duration(seconds: 3)));
    final b = load('b');
    final s1 = compute([a, b]);
    expect(s1.current!.load.id, 'a');
    final s2 = compute([a, b], skipped: {s1.current!.key});
    expect(s2.current!.load.id, 'b');
    final raised = load('a', created: t0.subtract(const Duration(seconds: 3)), budget: 21000, touched: t0);
    final s3 = compute([raised, b], skipped: {s1.current!.key});
    expect(ids(s3), contains('a'), reason: 'a different price is a different key');
    expect(s3.current!.opensAt, t0.subtract(const Duration(seconds: 0)), reason: 'the window restarts when the customer asked again');
    expect(s3.current!.secondsLeft(t0), 30);
  });

  test('widening the search makes a farther driver see it (ring boost), and an invited driver sees it at once', () {
    expect(compute([load('a')], origin: mid).current, isNull);
    expect(ids(compute([load('a', boost: 1)], origin: mid)), ['a']);
    const far = (lat: 28.9139, lng: 77.2090);
    expect(compute([load('a')], origin: far, seconds: 20).current, isNull);
    expect(ids(compute([load('a', invited: 'd1')], origin: far)), ['a']);
  });

  test('with the switch off every open load that fits is a card at once (old model)', () {
    expect(ids(compute([load('a')], origin: mid, waves: false)), ['a']);
  });

  test('a load not yet stamped by the server is not a card; a driver with no known place waits for the last ring', () {
    final unstamped = Load(id: 'u', shipperId: 'c1', pickup: 'Delhi', drop: 'Jaipur', cargoType: 'x', weight: 1, vehicleType: '14ft', budget: 1, pickupDate: null, notes: '', status: 'open');
    expect(compute([unstamped]).current, isNull);
    expect(compute([load('a')], origin: null, seconds: 10).current, isNull);
    expect(ids(compute([load('a')], origin: null, seconds: 60)), ['a']);
  });

  test('the same input always gives the same state', () {
    final loads = [load('a'), load('b', created: t0.subtract(const Duration(seconds: 2)))];
    expect(ids(compute(loads)), ids(compute(loads.reversed.toList())));
  });

  group('LoadRadar service', () {
    test('publishes the card, moves on when it expires, and closes cleanly', () async {
      var now = t0;
      final feed = StreamController<List<Load>>();
      final radar = LoadRadar(
        loads: feed.stream,
        vehicles: () async => [truck()],
        origin: () => near,
        driverId: () => 'd1',
        wavesOn: () => true,
        config: () => cfg,
        now: () => now,
        tick: const Duration(milliseconds: 20),
      );
      final seen = <String?>[];
      final sub = radar.states.listen((s) => seen.add(s.current?.load.id));
      radar.start();
      feed.add([load('a'), load('b', created: t0.add(const Duration(seconds: 5)))]);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(radar.state.current?.load.id, 'a');
      expect(radar.state.waiting, 0, reason: 'b is not open yet at t0');
      now = t0.add(const Duration(seconds: 6));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(radar.state.waiting, 1);
      radar.skip(radar.state.current!);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(radar.state.current?.load.id, 'b');
      now = t0.add(const Duration(seconds: 60));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(radar.state.current, isNull);
      await sub.cancel();
      await radar.dispose();
      await feed.close();
      expect(seen, contains('a'));
      expect(seen, contains('b'));
    });
  });
}
