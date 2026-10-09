import '../matching/load_ranker.dart';
import '../models/load.dart';
import '../models/vehicle.dart';
import '../pricing/cities.dart';

/// A driver the admin can suggest for an unfilled load (MASTER-6 Task 4).
class DispatchCandidate {
  final String driverId;
  final String vehicleId;
  final String vehicleNumber;

  /// Distance from the driver's last known spot to the pickup city, km;
  /// null when either is unknown (these sort last).
  final double? km;
  const DispatchCandidate({required this.driverId, required this.vehicleId, required this.vehicleNumber, this.km});
}

class Dispatch {
  Dispatch._();

  static const maxCandidates = 5;
  static const maxNote = 300;

  /// Nearest drivers whose free, legal vehicle fits [load]. One entry per
  /// driver (their nearest-fitting vehicle). [spotOf] gives the last spot of
  /// the vehicle's driver (assigned driver, else the owner).
  static List<DispatchCandidate> suggest(
    Load load,
    Iterable<Vehicle> vehicles, {
    required ({double lat, double lng})? Function(Vehicle) spotOf,
    required DateTime now,
    int limit = maxCandidates,
  }) {
    final pickup = findCity(load.pickup);
    final best = <String, DispatchCandidate>{};
    for (final v in vehicles) {
      if (!LoadRanker.vehicleFits(v, vehicleType: load.vehicleType, weight: load.weight, now: now)) continue;
      final driverId = v.assignedDriverId ?? v.ownerId;
      if (driverId == load.shipperId) continue; // never the person who posted it
      final spot = spotOf(v);
      final km = pickup == null || spot == null ? null : haversineKm(spot.lat, spot.lng, pickup.lat, pickup.lng);
      final c = DispatchCandidate(driverId: driverId, vehicleId: v.id, vehicleNumber: v.number, km: km);
      final old = best[driverId];
      if (old == null || _before(c, old)) best[driverId] = c;
    }
    final all = best.values.toList()..sort((a, b) => _before(a, b) ? -1 : (_before(b, a) ? 1 : a.driverId.compareTo(b.driverId)));
    return all.take(limit).toList();
  }

  static bool _before(DispatchCandidate a, DispatchCandidate b) {
    if (a.km == null) return false;
    if (b.km == null) return true;
    return a.km! < b.km!;
  }

  /// `dispatch_suggestions/{loadId}_{driverId}`.
  static String suggestionId(String loadId, String driverId) => '${loadId}_$driverId';
}
