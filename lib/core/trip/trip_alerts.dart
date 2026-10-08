import '../geo/trip_watcher.dart';
import '../models/booking.dart';
import '../pricing/cities.dart';

/// Per-stop progress (T7): the stops of a booking in order, marked reached
/// when the phone comes within [TripWatcher.reachedKm] of the stop's city.
/// Stops that are not in the offline city table cannot be tracked and are
/// left out of the count. LATER(paid): exact stop addresses from a geocoder.
class StopTracker {
  final List<String> stops;
  final List<({double lat, double lng})?> _points;
  final Set<int> _reached = {};

  StopTracker(this.stops) : _points = [for (final s in stops) _point(s)];

  static ({double lat, double lng})? _point(String place) {
    final c = findCity(place);
    return c == null ? null : (lat: c.lat, lng: c.lng);
  }

  /// A position sample. Returns the indexes reached by this sample for the first time.
  List<int> add(double lat, double lng) {
    final fresh = <int>[];
    for (var i = 0; i < _points.length; i++) {
      final p = _points[i];
      if (p == null || _reached.contains(i)) continue;
      if (haversineKm(lat, lng, p.lat, p.lng) <= TripWatcher.reachedKm) {
        _reached.add(i);
        fresh.add(i);
      }
    }
    _last = (lat: lat, lng: lng);
    return fresh;
  }

  ({double lat, double lng})? _last;

  bool reached(int i) => _reached.contains(i);
  int get reachedCount => _reached.length;
  int get trackable => _points.where((p) => p != null).length;

  /// First trackable stop not reached yet.
  int? get nextIndex {
    for (var i = 0; i < _points.length; i++) {
      if (_points[i] != null && !_reached.contains(i)) return i;
    }
    return null;
  }

  /// Straight-line km from the last sample to the next stop.
  double? get kmToNext {
    final i = nextIndex;
    if (i == null || _last == null) return null;
    return haversineKm(_last!.lat, _last!.lng, _points[i]!.lat, _points[i]!.lng);
  }
}

/// Km from a delivery or pickup GPS point to the booking's city centre when
/// it is further than [mismatchKm] (F10, F11), otherwise null. City centres
/// are generous (loading points sit on the outskirts), so the limit is wide.
const mismatchKm = 60.0;

double? gpsMismatchKm(double lat, double lng, String place) {
  final c = findCity(place);
  if (c == null) return null;
  final km = haversineKm(lat, lng, c.lat, c.lng);
  return km > mismatchKm ? km : null;
}

/// The driver is close enough to the pickup to warn the customer (N2).
const arrivingAlertKm = 25.0;

/// Plain text of a trip for the emergency contacts of the user (SAFE2). Kept
/// in English on purpose, like the other share texts: the contact may not use
/// the same language, and there is no deep link yet.
String tripSummaryText(Booking b, {String? who, String? link}) => [
      'LoadGo trip${who == null || who.isEmpty ? '' : ' of $who'}: ${b.route.join(' -> ')}',
      'Status: ${b.status.replaceAll('_', ' ')}',
      '${b.cargoType}, ${b.weight} T',
      if (b.vehicleNumber.isNotEmpty) 'Vehicle: ${b.vehicleNumber} (${b.vehicleType})',
      if (b.driverName.isNotEmpty) 'Driver: ${b.driverName}',
      if (b.lastKnownLocation != null) 'Last seen: https://maps.google.com/?q=${b.lastKnownLocation!.latitude.toStringAsFixed(4)},${b.lastKnownLocation!.longitude.toStringAsFixed(4)}',
      if (link != null) 'Follow this trip (valid 24 hours): $link',
      'Booking ID: ${b.id}',
    ].join('\n');
