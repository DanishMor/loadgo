import '../location/geohash.dart';
import '../models/load.dart';
import '../pricing/cities.dart';

typedef LatLng = ({double lat, double lng});

/// A load with its estimated distance from the driver (null = unknown place).
class NearLoad {
  final Load load;
  final int? km;
  const NearLoad(this.load, this.km);
}

/// Estimated road km from [origin] to the load's pickup city: straight line
/// x road factor, rounded up, at least 1. Null when the pickup is not in the
/// offline city table. LATER(paid): real road distance from a Maps API.
int? kmToPickup(LatLng origin, Load load, {double roadFactor = 1.25}) {
  final city = findCity(load.pickup);
  if (city == null) return null;
  final km = (haversineKm(origin.lat, origin.lng, city.lat, city.lng) * roadFactor).ceil();
  return km < 1 ? 1 : km;
}

/// Nearest pickup first. Loads with an unknown pickup keep their order at
/// the end; ties keep the incoming (newest first) order.
List<NearLoad> sortNearestFirst(List<Load> loads, LatLng origin) {
  final items = [for (final l in loads) NearLoad(l, kmToPickup(origin, l))];
  final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
  indexed.sort((a, b) {
    final ka = a.$2.km, kb = b.$2.km;
    if (ka == null && kb == null) return a.$1.compareTo(b.$1);
    if (ka == null) return 1;
    if (kb == null) return -1;
    final c = ka.compareTo(kb);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// Geohash of the city a free-text pickup names (7 characters, ~150 m, the
/// city centre), or null when the place is not in the offline city table.
/// Loads store it as `pickupGeohash` for the driver's nearby query.
/// LATER(paid): geocode the exact address with a Maps API.
String? pickupGeohashFor(String place) {
  final c = findCity(place);
  return c == null ? null : geohashEncode(c.lat, c.lng, precision: 7);
}
