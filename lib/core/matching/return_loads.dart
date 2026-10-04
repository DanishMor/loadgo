import '../models/booking.dart';
import '../models/load.dart';
import '../pricing/cities.dart';

/// An open load that starts near where a trip ends.
class ReturnLoad {
  final Load load;

  /// Estimated km from the trip's drop to this load's pickup.
  final int pickupKm;

  /// True when the load also ends near where the trip started (a real return).
  final bool towardsHome;

  const ReturnLoad(this.load, this.pickupKm, this.towardsHome);
}

/// Loads for the way back (Vahak / BlackBuck style): open loads whose pickup
/// is within [radiusKm] of [trip]'s drop city, ones heading back near the
/// trip's start first, then nearest pickup first. Pure and offline: uses the
/// city table, so unknown places never match. LATER(paid): real road
/// distance and a route corridor.
List<ReturnLoad> returnLoadsFor(Booking trip, Iterable<Load> openLoads, {int radiusKm = 100, String? excludeShipperId}) {
  final dropCity = findCity(trip.drop);
  if (dropCity == null) return const [];
  final homeCity = findCity(trip.pickup);
  final out = <ReturnLoad>[];
  for (final l in openLoads) {
    if (!l.isOpen || l.shipperId == excludeShipperId || l.id == trip.loadId) continue;
    final p = findCity(l.pickup);
    if (p == null) continue;
    final km = roadKmBetween(dropCity, p);
    if (km > radiusKm) continue;
    final d = findCity(l.drop);
    final home = homeCity != null && d != null && roadKmBetween(homeCity, d) <= radiusKm;
    out.add(ReturnLoad(l, km, home));
  }
  out.sort((a, b) {
    if (a.towardsHome != b.towardsHome) return a.towardsHome ? -1 : 1;
    return a.pickupKm.compareTo(b.pickupKm);
  });
  return out;
}
