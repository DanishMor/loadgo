import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/dispatch/dispatch_models.dart';
import 'package:transport_app/core/dispatch/dispatch_window.dart';
import 'package:transport_app/core/models/load.dart';

/// U11: who sees a load, and when (the client layer of the waves).
void main() {
  final t0 = DateTime(2030, 1, 1, 12);
  const w = DispatchWindow();

  Load load({String pickup = 'Delhi', int boost = 0, LoadMode mode = LoadMode.instant, DateTime? created, String? invited, bool noTime = false}) => Load(
        id: 'L1',
        shipperId: 'c1',
        pickup: pickup,
        drop: 'Jaipur',
        cargoType: 'FMCG',
        weight: 5,
        vehicleType: '20ft',
        budget: null,
        pickupDate: null,
        notes: '',
        status: 'open',
        createdAt: noTime ? null : Timestamp.fromDate(created ?? t0),
        ringBoost: boost,
        mode: mode,
        invitedDriverId: invited,
      );

  // Delhi centre is 28.6139, 77.2090. Straight km x 1.25 road factor decides the ring.
  const near = (lat: 28.6239, lng: 77.2090); // about 2 km by road: ring 1 (3 km)
  const mid = (lat: 28.6539, lng: 77.2090); // about 5.6 km: ring 2 (7 km)
  const far = (lat: 28.6939, lng: 77.2090); // about 11 km: ring 3 (15 km)
  const outside = (lat: 28.9139, lng: 77.2090); // about 41 km: outside every ring

  bool sees(({double lat, double lng})? o, int secondsAfter, {Load? l}) => w.isVisibleTo(l ?? load(), origin: o, now: t0.add(Duration(seconds: secondsAfter)));

  test('the nearest ring sees the load at once, the next after 30 s, the third after 60 s, nobody outside', () {
    expect(sees(near, 0), isTrue);
    expect(sees(mid, 0), isFalse);
    expect(sees(mid, 29), isFalse);
    expect(sees(mid, 30), isTrue);
    expect(sees(far, 59), isFalse);
    expect(sees(far, 60), isTrue);
    expect(sees(outside, 0), isFalse);
    expect(sees(outside, 3600), isFalse);
  });

  test('a driver inside an inner ring keeps seeing the load as the rings open', () {
    for (final s in [0, 10, 30, 60, 600]) {
      expect(sees(near, s), isTrue, reason: '$s s');
    }
  });

  test('an unknown driver place or an unknown pickup is shown when the last wave opens, never hidden for good', () {
    expect(sees(null, 59), isFalse);
    expect(sees(null, 60), isTrue);
    expect(sees(near, 0, l: load(pickup: 'Nowhereville')), isFalse);
    expect(sees(near, 60, l: load(pickup: 'Nowhereville')), isTrue);
  });

  test('widening the search by one ring: every wave reaches one ring further', () {
    expect(sees(mid, 0, l: load(boost: 1)), isTrue, reason: '5.6 km is inside the 7 km ring that now opens at once');
    expect(sees(far, 0, l: load(boost: 1)), isFalse);
    expect(sees(far, 30, l: load(boost: 1)), isTrue);
    expect(sees(outside, 600, l: load(boost: 3)), isFalse, reason: 'the widest ring is still 15 km');
  });

  test('scheduled loads have no waves; an invited driver sees the load at once; a load without its server time counts as just posted', () {
    expect(sees(far, 0, l: load(mode: LoadMode.scheduled)), isTrue);
    expect(sees(outside, 0, l: load(mode: LoadMode.scheduled)), isFalse);
    expect(w.isVisibleTo(load(invited: 'd9'), origin: outside, now: t0, driverId: 'd9'), isTrue);
    expect(w.isVisibleTo(load(invited: 'd9'), origin: outside, now: t0, driverId: 'd8'), isFalse);
    expect(sees(mid, 0, l: load(noTime: true)), isFalse);
    expect(sees(near, 0, l: load(noTime: true)), isTrue);
  });

  test('timeUntilVisible counts down, is zero when visible and null when never', () {
    expect(w.timeUntilVisible(km: 5.6, createdAt: t0, now: t0.add(const Duration(seconds: 10))), const Duration(seconds: 20));
    expect(w.timeUntilVisible(km: 5.6, createdAt: t0, now: t0.add(const Duration(seconds: 31))), Duration.zero);
    expect(w.timeUntilVisible(km: 99, createdAt: t0, now: t0), isNull);
  });

  test('another configuration (a city with smaller rings) is respected', () {
    final c = DispatchWindow(DispatchConfig.fromMap({'ringsKm': [1, 2, 4], 'ringDelaySeconds': [0, 10, 20]}));
    expect(c.isVisible(km: 3, createdAt: t0, now: t0.add(const Duration(seconds: 19))), isFalse);
    expect(c.isVisible(km: 3, createdAt: t0, now: t0.add(const Duration(seconds: 20))), isTrue);
    expect(c.isVisible(km: 5, createdAt: t0, now: t0.add(const Duration(hours: 1))), isFalse);
  });

  test('filter keeps the order and drops what is not unlocked yet', () {
    final a = load(created: t0), b = load(created: t0.subtract(const Duration(seconds: 100)));
    expect(w.filter([a, b], origin: far, now: t0), [b]);
    expect(w.filter([a, b], origin: near, now: t0), [a, b]);
  });
}
