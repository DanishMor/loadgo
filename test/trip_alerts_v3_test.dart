import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/geo/trip_watcher.dart';

/// E37 (flag tripAlerts): the route-deviation signal of the trip watcher.
void main() {
  final t0 = DateTime(2027, 5, 20, 10);
  const pune = (lat: 18.5204, lng: 73.8567);
  const mumbai = (lat: 19.0760, lng: 72.8777);

  test('distance to the pickup-drop line: zero on it, real km beside it, ends clamp', () {
    expect(TripWatcher.distToSegmentKm(pune, pune, mumbai), closeTo(0, 0.01));
    final mid = (lat: (pune.lat + mumbai.lat) / 2, lng: (pune.lng + mumbai.lng) / 2);
    expect(TripWatcher.distToSegmentKm(mid, pune, mumbai), closeTo(0, 0.5));
    const nashik = (lat: 19.9975, lng: 73.7898);
    expect(TripWatcher.distToSegmentKm(nashik, pune, mumbai), greaterThan(100));
    expect(TripWatcher.offRouteKm(200), 80);
  });

  test('off route needs two fixes in a row beyond the limit; off without a pickup', () {
    final w = TripWatcher(pickupPoint: pune, dropPoint: mumbai);
    w.add(t0, 19.9975, 73.7898); // Nashik, far off the Pune-Mumbai line
    expect(w.signals(t0).offRoute, isFalse, reason: 'one fix is not enough');
    w.add(t0.add(const Duration(minutes: 5)), 20.0, 73.8);
    final s = w.signals(t0.add(const Duration(minutes: 5)));
    expect(s.offRoute, isTrue);
    expect(s.kmOffRoute, greaterThan(100));
    expect(s.any, isTrue);

    final noPickup = TripWatcher(dropPoint: mumbai)
      ..add(t0, 19.9975, 73.7898)
      ..add(t0.add(const Duration(minutes: 5)), 20.0, 73.8);
    expect(noPickup.signals(t0.add(const Duration(minutes: 5))).offRoute, isFalse);
  });

  test('on the way and near the drop never count as off route', () {
    final w = TripWatcher(pickupPoint: pune, dropPoint: mumbai)
      ..add(t0, 18.75, 73.4)
      ..add(t0.add(const Duration(minutes: 5)), 18.76, 73.38);
    expect(w.signals(t0.add(const Duration(minutes: 5))).offRoute, isFalse);
  });
}
