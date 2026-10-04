import '../core/services/location_service.dart';
import '../core/services/user_service.dart';

/// Saves the driver's position on the profile, at most once every few
/// minutes, only when the OS location permission is granted. Never throws.
class DriverLocationSync {
  DriverLocationSync._();

  static const minGap = Duration(minutes: 5);
  static DateTime? _lastSaved;

  static Future<bool> refresh({DateTime? now}) async {
    final t = now ?? DateTime.now();
    if (_lastSaved != null && t.difference(_lastSaved!) < minGap) return false;
    try {
      final pos = await LocationService.current();
      if (pos == null) return false;
      await UserService.saveDriverLocation(pos.lat, pos.lng);
      _lastSaved = t;
      return true;
    } catch (_) {
      return false;
    }
  }

  static void resetForTest() => _lastSaved = null;
}
