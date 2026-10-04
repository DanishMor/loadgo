import '../models/load.dart';
import '../pricing/cities.dart';

/// Open loads in one pickup city.
class CityDemand {
  final String city;

  /// Open loads starting here.
  final int loads;

  /// Vehicle type id -> open loads wanting it, most wanted first.
  final Map<String, int> byType;

  const CityDemand({required this.city, required this.loads, required this.byType});

  String? get topType => byType.isEmpty ? null : byType.keys.first;
}

/// Where the open loads are and which vehicle types they ask for. Pure; works
/// on the loads the app already has (the open list), not on a server count.
/// LATER(paid): a heat map on Maps and a Cloud Function that counts every
/// open load.
class DemandSummary {
  /// Cities, busiest first (ties by name). Pickups outside the city table
  /// are grouped as [otherLabel].
  final List<CityDemand> cities;

  /// Vehicle type id -> open loads wanting it across all cities.
  final Map<String, int> byType;
  final int totalLoads;

  const DemandSummary({required this.cities, required this.byType, required this.totalLoads});

  static const otherLabel = '';

  static Map<String, int> _sorted(Map<String, int> m) {
    final entries = m.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    return {for (final e in entries) e.key: e.value};
  }

  factory DemandSummary.from(Iterable<Load> loads, {String? excludeShipperId}) {
    final perCity = <String, Map<String, int>>{};
    final overall = <String, int>{};
    var total = 0;
    for (final l in loads) {
      if (!l.isOpen || l.shipperId == excludeShipperId) continue;
      total++;
      final city = findCity(l.pickup)?.name ?? otherLabel;
      final types = perCity.putIfAbsent(city, () => {});
      types[l.vehicleType] = (types[l.vehicleType] ?? 0) + 1;
      overall[l.vehicleType] = (overall[l.vehicleType] ?? 0) + 1;
    }
    final cities = [
      for (final e in perCity.entries)
        CityDemand(city: e.key, loads: e.value.values.fold(0, (a, b) => a + b), byType: _sorted(e.value)),
    ]..sort((a, b) {
        // "Other" always last.
        if (a.city == otherLabel) return 1;
        if (b.city == otherLabel) return -1;
        final c = b.loads.compareTo(a.loads);
        return c != 0 ? c : a.city.compareTo(b.city);
      });
    return DemandSummary(cities: cities, byType: _sorted(overall), totalLoads: total);
  }
}
