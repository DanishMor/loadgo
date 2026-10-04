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

  const TripSignals({this.nearDestination = false, this.destinationReached = false, this.longHalt = false, this.kmToDrop});

  bool get any => nearDestination || destinationReached || longHalt;
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
  final List<({DateTime at, double lat, double lng})> _samples = [];

  TripWatcher({String? dropPlace, ({double lat, double lng})? dropPoint})
      : drop = dropPoint ?? _cityPoint(dropPlace);

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
    return TripSignals(nearDestination: near && !reached, destinationReached: reached, longHalt: halt, kmToDrop: km);
  }
}
