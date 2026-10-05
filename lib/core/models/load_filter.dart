import 'load.dart';

/// Driver-side filter for open loads. Empty fields don't filter.
class LoadFilter {
  final String pickupQuery;
  final String dropQuery;
  final String? vehicleType;

  /// Budget range (rupees). Loads without a budget (negotiable) are excluded
  /// when either end is set.
  final num? minBudget;
  final num? maxBudget;

  /// Weight range in tons.
  final num? minWeight;
  final num? maxWeight;

  /// Pickup date range (whole days, both ends included). Loads without a
  /// pickup date are excluded when either end is set.
  final DateTime? fromDate;
  final DateTime? toDate;

  const LoadFilter({
    this.pickupQuery = '',
    this.dropQuery = '',
    this.vehicleType,
    this.minBudget,
    this.maxBudget,
    this.minWeight,
    this.maxWeight,
    this.fromDate,
    this.toDate,
  });

  static const none = LoadFilter();

  bool get isEmpty => pickupQuery.trim().isEmpty && sheetFilterCount == 0;

  /// Number of sheet filters in use (the pickup search box is shown separately).
  int get sheetFilterCount => [
        dropQuery.trim().isNotEmpty,
        vehicleType != null,
        minBudget != null,
        maxBudget != null,
        minWeight != null,
        maxWeight != null,
        fromDate != null,
        toDate != null,
      ].where((b) => b).length;

  LoadFilter copyWith({
    String? pickupQuery,
    String? dropQuery,
    String? Function()? vehicleType,
    num? Function()? minBudget,
    num? Function()? maxBudget,
    num? Function()? minWeight,
    num? Function()? maxWeight,
    DateTime? Function()? fromDate,
    DateTime? Function()? toDate,
  }) =>
      LoadFilter(
        pickupQuery: pickupQuery ?? this.pickupQuery,
        dropQuery: dropQuery ?? this.dropQuery,
        vehicleType: vehicleType != null ? vehicleType() : this.vehicleType,
        minBudget: minBudget != null ? minBudget() : this.minBudget,
        maxBudget: maxBudget != null ? maxBudget() : this.maxBudget,
        minWeight: minWeight != null ? minWeight() : this.minWeight,
        maxWeight: maxWeight != null ? maxWeight() : this.maxWeight,
        fromDate: fromDate != null ? fromDate() : this.fromDate,
        toDate: toDate != null ? toDate() : this.toDate,
      );

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  bool matches(Load load) {
    final q = pickupQuery.trim().toLowerCase();
    if (q.isNotEmpty && !load.pickup.toLowerCase().contains(q)) return false;
    final dq = dropQuery.trim().toLowerCase();
    if (dq.isNotEmpty && !load.drop.toLowerCase().contains(dq)) return false;
    if (vehicleType != null && load.vehicleType != vehicleType) return false;
    if (minBudget != null && (load.budget == null || load.budget! < minBudget!)) return false;
    if (maxBudget != null && (load.budget == null || load.budget! > maxBudget!)) return false;
    if (minWeight != null && load.weight < minWeight!) return false;
    if (maxWeight != null && load.weight > maxWeight!) return false;
    if (fromDate != null || toDate != null) {
      final p = load.pickupDate;
      if (p == null) return false;
      if (fromDate != null && _day(p).isBefore(_day(fromDate!))) return false;
      if (toDate != null && _day(p).isAfter(_day(toDate!))) return false;
    }
    return true;
  }

  List<Load> apply(Iterable<Load> loads) => loads.where(matches).toList();

  /// Stored form of a saved search (only the fields in use).
  Map<String, Object?> toMap() => {
        if (pickupQuery.trim().isNotEmpty) 'pickup': pickupQuery.trim(),
        if (dropQuery.trim().isNotEmpty) 'drop': dropQuery.trim(),
        'vehicleType': ?vehicleType,
        'minBudget': ?minBudget,
        'maxBudget': ?maxBudget,
        'minWeight': ?minWeight,
        'maxWeight': ?maxWeight,
        if (fromDate != null) 'from': _iso(fromDate!),
        if (toDate != null) 'to': _iso(toDate!),
      };

  factory LoadFilter.fromMap(Map<String, dynamic> m) => LoadFilter(
        pickupQuery: m['pickup'] as String? ?? '',
        dropQuery: m['drop'] as String? ?? '',
        vehicleType: m['vehicleType'] as String?,
        minBudget: m['minBudget'] as num?,
        maxBudget: m['maxBudget'] as num?,
        minWeight: m['minWeight'] as num?,
        maxWeight: m['maxWeight'] as num?,
        fromDate: parseIsoDate(m['from']),
        toDate: parseIsoDate(m['to']),
      );
}

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// "2026-10-05" -> local date; null for anything else.
DateTime? parseIsoDate(Object? v) {
  if (v is! String) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(v);
  return m == null ? null : DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}
