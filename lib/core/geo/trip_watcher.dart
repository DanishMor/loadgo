import 'dart:math';

import '../pricing/cities.dart';

/// A circle on the map (M14): a pickup, drop, warehouse or port boundary.
class Geofence {
  final double lat;
  final double lng;
  final double radiusKm;
  const Geofence(this.lat, this.lng, this.radiusKm);

  bool contains(double pLat, double pLng) => haversineKm(lat, lng, pLat, pLng) <= radiusKm;
}

/// What the driver's position says about a trip in transit.
class TripSignals {
  /// Within [TripWatcher.nearKm] of the drop: tell the receiver to get ready.
  final bool nearDestination;

  /// Within [TripWatcher.reachedKm] of the drop: unloading can start.
  final bool destinationReached;

  /// Barely moved for [TripWatcher.haltMinutes] minutes.
  final bool longHalt;

  /// Straight-line km to the drop, if known.
  final double? kmToDrop;

  /// E37 (flag tripAlerts): far from the line between pickup and drop (see [TripWatcher.offRouteKm]).
  final bool offRoute;

  /// How far off that line the truck is, when known.
  final double? kmOffRoute;

  const TripSignals({this.nearDestination = false, this.destinationReached = false, this.longHalt = false, this.kmToDrop, this.offRoute = false, this.kmOffRoute});

  bool get any => nearDestination || destinationReached || longHalt || offRoute;
}

/// Pure geofence logic over position samples (no GPS plugin in here, so it
/// is testable). The drop is a city centre from the offline table, so the
/// radii are generous. LATER(paid): exact addresses from a geocoder.
class TripWatcher {
  static const nearKm = 25.0;
  static const reachedKm = 5.0;
  static const haltMinutes = 30;

  /// Movement under this many km over the halt window counts as standing still.
  static const haltRadiusKm = 0.3;

  final ({double lat, double lng})? drop;

  /// E37: the pickup, for the route-deviation check; null switches it off (the default).
  final ({double lat, double lng})? pickup;
  final List<({DateTime at, double lat, double lng})> _samples = [];

  TripWatcher({String? dropPlace, ({double lat, double lng})? dropPoint, String? pickupPlace, ({double lat, double lng})? pickupPoint})
      : drop = dropPoint ?? _cityPoint(dropPlace),
        pickup = pickupPoint ?? _cityPoint(pickupPlace);

  /// E37: off route when the straight-line distance to the pickup-drop line is over 50 km plus 15% of the trip
  /// length (roads bend; the places are city centres). Two samples in a row must agree, so one bad GPS fix does
  /// not raise it.
  static double offRouteKm(double tripKm) => 50 + 0.15 * tripKm;

  static double distToSegmentKm(({double lat, double lng}) p, ({double lat, double lng}) a, ({double lat, double lng}) b) {
    // Flat projection around the segment; fine at these distances.
    final k = 111.32 * cos(a.lat * pi / 180);
    final ax = a.lng * k, ay = a.lat * 110.57, bx = b.lng * k, by = b.lat * 110.57, px = p.lng * k, py = p.lat * 110.57;
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    final t = len2 == 0 ? 0.0 : (((px - ax) * dx + (py - ay) * dy) / len2).clamp(0.0, 1.0);
    final cx = ax + t * dx, cy = ay + t * dy;
    return sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
  }

  double? _offBy(({DateTime at, double lat, double lng}) s) {
    if (pickup == null || drop == null) return null;
    return distToSegmentKm((lat: s.lat, lng: s.lng), pickup!, drop!);
  }

  static ({double lat, double lng})? _cityPoint(String? place) {
    final c = place == null ? null : findCity(place);
    return c == null ? null : (lat: c.lat, lng: c.lng);
  }

  void add(DateTime at, double lat, double lng) {
    _samples.add((at: at, lat: lat, lng: lng));
    // Keep two hours; older samples cannot matter.
    _samples.removeWhere((s) => at.difference(s.at) > const Duration(hours: 2));
  }

  TripSignals signals(DateTime now) {
    if (_samples.isEmpty) return const TripSignals();
    final last = _samples.last;
    final km = drop == null ? null : haversineKm(last.lat, last.lng, drop!.lat, drop!.lng);
    final reached = km != null && km <= reachedKm;
    final near = km != null && km <= nearKm;

    // Halt: the samples cover the whole window and none strayed from the
    // latest spot. The last sample from before the window counts too, so
    // silence for 30 minutes at one spot is a halt.
    final windowStart = now.subtract(const Duration(minutes: haltMinutes));
    final relevant = _samples.where((s) => !s.at.isBefore(windowStart)).toList();
    ({DateTime at, double lat, double lng})? anchor;
    for (final s in _samples) {
      if (!s.at.isAfter(windowStart)) anchor = s;
    }
    if (anchor != null) relevant.add(anchor);
    final covers = anchor != null || (relevant.isNotEmpty && now.difference(_samples.first.at).inMinutes >= haltMinutes);
    final still = relevant.isNotEmpty && relevant.every((s) => haversineKm(s.lat, s.lng, last.lat, last.lng) <= haltRadiusKm);
    final halt = covers && still && !reached;
    final off = _offBy(last);
    final limit = pickup == null || drop == null ? null : offRouteKm(haversineKm(pickup!.lat, pickup!.lng, drop!.lat, drop!.lng));
    final prev = _samples.length >= 2 ? _offBy(_samples[_samples.length - 2]) : null;
    final offRoute = off != null && limit != null && prev != null && off > limit && prev > limit && !near && !reached;
    return TripSignals(nearDestination: near && !reached, destinationReached: reached, longHalt: halt, kmToDrop: km, offRoute: offRoute, kmOffRoute: off);
  }
}
