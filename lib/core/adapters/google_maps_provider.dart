import '../services/server_actions.dart';
import 'maps_adapter.dart';

/// Road distance and time through the `mapsRoute` function (G10). The Maps key
/// stays on the server; the server caches answers and limits each person per day.
/// Geocoding is not done here: places come from the built-in city table or the
/// phone's own position, so no per-search charge exists.
/// Any problem (switch off, not deployed, offline, daily limit) is a null answer
/// and the app uses the city table as before.
class GoogleMapsProvider implements MapsProvider {
  final ServerGateway server;
  GoogleMapsProvider([ServerGateway? server]) : server = server ?? ServerActions.gateway;

  /// Set when the server said the person's turns for today are used up.
  static bool outOfTurnsToday = false;
  static int _dayOfLimit = -1;

  static bool get limited => outOfTurnsToday && _dayOfLimit == DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)).day;

  @override
  Future<GeoPoint2?> geocode(String place) async => null;

  @override
  Future<RouteInfo?> route(GeoPoint2 from, GeoPoint2 to) async {
    if (limited) return null;
    try {
      final r = await server.call('mapsRoute', {
        'from': {'lat': from.lat, 'lng': from.lng},
        'to': {'lat': to.lat, 'lng': to.lng},
      });
      final m = r['meters'];
      final s = r['seconds'];
      if (m is! int || m <= 0 || m > 10000000) return null;
      return RouteInfo(m, s is int && s >= 0 ? s : 0);
    } catch (e) {
      if ('$e'.contains('resource-exhausted')) {
        outOfTurnsToday = true;
        _dayOfLimit = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)).day;
      }
      return null;
    }
  }
}
