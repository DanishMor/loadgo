import '../adapters/google_maps_provider.dart';
import '../adapters/maps_adapter.dart';
import '../features/features.dart';
import '../pricing/cities.dart';
import '../services/features_service.dart';

/// G10: real road kilometres between the cities of a route, when the `maps`
/// switch is on and the server answers. Everything is optional: [kmFor] gives
/// null until every leg is known and the caller then keeps the city-table
/// distance, so with the switch off nothing changes.
class RoadDistance {
  RoadDistance._();

  static MapsProvider provider = GoogleMapsProvider();
  static final Map<String, int> _km = {};
  static final Set<String> _asked = {};

  static bool get enabled => FeaturesService.isOn(FeatureKey.maps);

  static String _key(City a, City b) => '${a.name}|${b.name}';

  /// Road km of the whole route when every leg has an answer, else null.
  static int? kmFor(List<String> places) {
    if (!enabled || places.length < 2) return null;
    var total = 0;
    for (var i = 0; i + 1 < places.length; i++) {
      final a = findCity(places[i]);
      final b = findCity(places[i + 1]);
      if (a == null || b == null) return null;
      if (a.name == b.name) continue;
      final km = _km[_key(a, b)];
      if (km == null) return null;
      total += km;
    }
    return total > 0 ? total : null;
  }

  /// Asks for the legs that are not known yet (each pair at most once per run).
  /// True when something new arrived, so the screen can redraw.
  static Future<bool> prefetch(List<String> places) async {
    if (!enabled || places.length < 2) return false;
    var got = false;
    for (var i = 0; i + 1 < places.length; i++) {
      final a = findCity(places[i]);
      final b = findCity(places[i + 1]);
      if (a == null || b == null || a.name == b.name) continue;
      final k = _key(a, b);
      if (_km.containsKey(k) || !_asked.add(k)) continue;
      final r = await provider.route(GeoPoint2(a.lat, a.lng), GeoPoint2(b.lat, b.lng));
      if (r != null && r.meters > 0) {
        _km[k] = (r.meters / 1000).ceil();
        got = true;
      }
    }
    return got;
  }

  static void reset() {
    _km.clear();
    _asked.clear();
    provider = GoogleMapsProvider();
  }
}
