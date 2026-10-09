class GeoPoint2 {
  final double lat;
  final double lng;
  const GeoPoint2(this.lat, this.lng);
}

class RouteInfo {
  /// Road distance in metres and driving time in seconds.
  final int meters;
  final int seconds;
  const RouteInfo(this.meters, this.seconds);
}

/// LATER(paid): Google Maps Platform (geocoding, distance matrix). Today the
/// app uses an offline table of cities and straight-line distance.
abstract class MapsProvider {
  /// Null when the place is not found.
  Future<GeoPoint2?> geocode(String place);
  Future<RouteInfo?> route(GeoPoint2 from, GeoPoint2 to);
}

class NoMapsProvider implements MapsProvider {
  const NoMapsProvider();
  @override
  Future<GeoPoint2?> geocode(String place) async => null;
  @override
  Future<RouteInfo?> route(GeoPoint2 from, GeoPoint2 to) async => null;
}

class FakeMapsProvider implements MapsProvider {
  final Map<String, GeoPoint2> places = {
    'delhi': const GeoPoint2(28.6139, 77.2090),
    'mumbai': const GeoPoint2(19.0760, 72.8777),
  };

  @override
  Future<GeoPoint2?> geocode(String place) async => places[place.trim().toLowerCase()];

  @override
  Future<RouteInfo?> route(GeoPoint2 from, GeoPoint2 to) async {
    final dLat = (from.lat - to.lat).abs();
    final dLng = (from.lng - to.lng).abs();
    // About 111 km per degree, roads 1.3 times the straight line, 40 km/h.
    final meters = ((dLat + dLng) * 111000 * 1.3).round();
    if (meters == 0) return const RouteInfo(0, 0);
    return RouteInfo(meters, (meters / (40000 / 3600)).round());
  }
}
