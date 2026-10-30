import 'package:cloud_firestore/cloud_firestore.dart';

import '../location/geohash.dart';
import '../pricing/cities.dart';
import '../services/backend.dart';
import 'connect_adapters.dart';
import 'maps_adapter.dart';

/// E36 (flag demandFeed): the DemandFeed that reads demand_cells, the open-load counts the server writes every ten
/// minutes (functions/src/demand.js). One query of at most 9 cells around the driver; counts older than 30 minutes
/// are ignored. Each cell is named after the nearest city in the offline table.
class FirestoreDemandFeed implements DemandFeed {
  final FirebaseFirestore? db;
  final DateTime Function() now;
  FirestoreDemandFeed({this.db, this.now = DateTime.now});

  static const cellLen = 4;
  static const maxAge = Duration(minutes: 30);

  @override
  Future<List<DemandCell>> near(GeoPoint2 at, {int max = 5}) async {
    if (at.lat.abs() > 90 || at.lng.abs() > 180 || max < 1) return const [];
    final size = geohashCellSize(cellLen);
    final centre = <String, (double, double)>{};
    for (final dLat in [-1, 0, 1]) {
      for (final dLng in [-1, 0, 1]) {
        final la = at.lat + dLat * size.lat, lo = at.lng + dLng * size.lng;
        if (la.abs() > 90 || lo.abs() > 180) continue;
        centre.putIfAbsent(geohashEncode(la, lo, precision: cellLen), () => (la, lo));
      }
    }
    try {
      final snap = await (db ?? Backend.db).collection('demand_cells').where(FieldPath.documentId, whereIn: centre.keys.toList()).limit(9).get();
      final fresh = now().subtract(maxAge);
      final out = <DemandCell>[];
      for (final d in snap.docs) {
        final n = d.data()['openLoads'], at = d.data()['updatedAt'];
        if (n is! int || n <= 0 || at is! Timestamp || at.toDate().isBefore(fresh)) continue;
        final (la, lo) = centre[d.id] ?? (0.0, 0.0);
        out.add(DemandCell(_nearestCity(la, lo), n));
      }
      out.sort((a, b) => b.openLoads.compareTo(a.openLoads));
      return out.take(max).toList();
    } catch (_) {
      return const [];
    }
  }

  static String _nearestCity(double lat, double lng) {
    City? best;
    var bestKm = double.infinity;
    for (final c in indianCities) {
      final km = haversineKm(lat, lng, c.lat, c.lng);
      if (km < bestKm) {
        bestKm = km;
        best = c;
      }
    }
    return best?.name ?? '';
  }
}
