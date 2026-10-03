import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

typedef Coordinates = ({double lat, double lng});

/// Streams the device position. Tests swap in a fake via [useFake].
class LocationService {
  LocationService._();

  static Stream<Coordinates> Function()? _fake;

  /// Asks for permission if needed; false when location can't be used.
  static Future<bool> ensurePermission() async {
    if (_fake != null) return true;
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    return perm == LocationPermission.always || perm == LocationPermission.whileInUse;
  }

  /// Position updates, at most one every ~50 m of movement.
  static Stream<Coordinates> positions() {
    if (_fake != null) return _fake!();
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 50),
    ).map((p) => (lat: p.latitude, lng: p.longitude));
  }

  @visibleForTesting
  static void useFake(Stream<Coordinates> Function()? fake) => _fake = fake;
}
