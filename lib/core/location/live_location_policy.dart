import '../pricing/cities.dart';
import '../services/location_service.dart';

/// G11: when a new position from the phone is worth a database write. Writes cost
/// money and battery, so a position is sent only if enough time has passed AND
/// the truck moved, or (as a heartbeat) when a long time has passed.
class LiveLocationConfig {
  /// Never two writes closer than this.
  final Duration minGap;

  /// Needed movement since the last write.
  final int minMoveMeters;

  /// Even a parked truck is shown as alive at this interval.
  final Duration heartbeat;

  const LiveLocationConfig({this.minGap = const Duration(seconds: 30), this.minMoveMeters = 100, this.heartbeat = const Duration(minutes: 5)});

  /// Reads `config/liveLocation`; every value is bounded so a typo cannot melt the battery or the bill.
  factory LiveLocationConfig.fromMap(Map<String, dynamic>? m) {
    int pick(Object? v, int fallback, int min, int max) => v is int && v >= min && v <= max ? v : fallback;
    return LiveLocationConfig(
      minGap: Duration(seconds: pick(m?['minGapSeconds'], 30, 10, 600)),
      minMoveMeters: pick(m?['minMoveMeters'], 100, 20, 5000),
      heartbeat: Duration(seconds: pick(m?['heartbeatSeconds'], 300, 60, 3600)),
    );
  }
}

class LiveLocationPolicy {
  final LiveLocationConfig config;
  DateTime? _lastAt;
  Coordinates? _last;

  LiveLocationPolicy([this.config = const LiveLocationConfig()]);

  bool shouldWrite(Coordinates c, DateTime now) {
    final at = _lastAt, last = _last;
    if (at == null || last == null) return true;
    final since = now.difference(at);
    if (since < config.minGap) return false;
    if (since >= config.heartbeat) return true;
    final meters = haversineKm(last.lat, last.lng, c.lat, c.lng) * 1000;
    return meters >= config.minMoveMeters;
  }

  void wrote(Coordinates c, DateTime now) {
    _lastAt = now;
    _last = c;
  }

  void reset() {
    _lastAt = null;
    _last = null;
  }
}
