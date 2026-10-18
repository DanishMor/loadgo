import '../matching/nearest.dart';
import '../models/load.dart';
import '../pricing/cities.dart';
import 'dispatch_models.dart';

/// Which drivers see a load, and when (U11). A load goes out in rings: the first ring (the
/// nearest drivers) at once, the next ring [DispatchConfig.ringDelaySeconds] later, and so on.
/// A driver sees the load when the distance from the driver to the pickup is inside a ring that
/// has already unlocked. The customer can widen the search ([Load.ringBoost]): every wave then
/// reaches that many rings further.
///
/// IMPORTANT: this is a client-side layer for the feed and the incoming-load card. It makes the
/// experience right but it is not a guard: a modified app could still read the load. The real
/// enforcement is the server wave (`dispatchWave`, switch `dispatchV2`), which comes with the
/// functions deploy. Nothing secret is in an open load; the rules are what protect money and trips.
class DispatchWindow {
  final DispatchConfig config;
  const DispatchWindow([this.config = DispatchConfig.defaults]);

  /// How far, in km, wave [i] reaches for a load with [boost] extra rings.
  int _reach(int i, int boost) {
    final last = config.ringsKm.length - 1;
    return config.ringsKm[(i + boost).clamp(0, last)];
  }

  /// The first wave (0-based) that includes a driver [km] away, or null when the driver is
  /// outside even the widest ring.
  int? waveFor(double km, {int boost = 0}) {
    for (var i = 0; i < config.ringsKm.length; i++) {
      if (km <= _reach(i, boost)) return i;
    }
    return null;
  }

  /// Seconds after posting when this driver first sees the load; null when never (too far).
  /// A driver whose distance is unknown (no location or a pickup not in the city table) sees it
  /// when the last wave opens, so a load is never hidden for good because of missing data.
  int? secondsUntilVisible(double? km, {int boost = 0}) {
    if (km == null) return config.ringDelaySeconds.last;
    final w = waveFor(km, boost: boost);
    return w == null ? null : config.ringDelaySeconds[w];
  }

  /// True when the load should be in this driver's feed now.
  bool isVisible({
    required double? km,
    required DateTime? createdAt,
    required DateTime now,
    int boost = 0,
    LoadMode mode = LoadMode.instant,
    bool invited = false,
  }) {
    if (invited) return true;
    // A load written a moment ago may not have its server time yet: it is just posted.
    final elapsed = createdAt == null ? 0 : now.difference(createdAt).inSeconds;
    if (mode == LoadMode.scheduled) {
      // A scheduled load has no waves: everyone inside the widest ring sees it, or anyone when the distance is unknown.
      return km == null || waveFor(km, boost: boost) != null;
    }
    final need = secondsUntilVisible(km, boost: boost);
    return need != null && elapsed >= need;
  }

  /// How long until the load shows for this driver; zero when it already does, null when never.
  Duration? timeUntilVisible({required double? km, required DateTime? createdAt, required DateTime now, int boost = 0, LoadMode mode = LoadMode.instant, bool invited = false}) {
    if (isVisible(km: km, createdAt: createdAt, now: now, boost: boost, mode: mode, invited: invited)) return Duration.zero;
    final need = secondsUntilVisible(km, boost: boost);
    if (need == null) return null;
    final elapsed = createdAt == null ? 0 : now.difference(createdAt).inSeconds;
    return Duration(seconds: need - elapsed);
  }

  /// [isVisible] for a load and a driver at [origin] (null when the driver's place is unknown).
  bool isVisibleTo(Load load, {required LatLng? origin, required DateTime now, String? driverId}) {
    final km = origin == null ? null : kmToPickup(origin, load)?.toDouble();
    // A city may have its own rings and times (config/dispatch, `cities`).
    final city = config.cities.isEmpty ? null : findCity(load.pickup)?.name;
    final w = city == null ? this : DispatchWindow(config.forCity(city));
    return w.isVisible(
      km: km,
      createdAt: load.createdAt?.toDate(),
      now: now,
      boost: load.ringBoost,
      mode: load.mode,
      invited: driverId != null && load.invitedDriverId == driverId,
    );
  }

  /// The feed filter: [loads] the driver may see now, in the same order.
  List<Load> filter(List<Load> loads, {required LatLng? origin, required DateTime now, String? driverId}) =>
      [for (final l in loads) if (isVisibleTo(l, origin: origin, now: now, driverId: driverId)) l];
}
