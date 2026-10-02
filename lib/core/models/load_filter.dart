import 'load.dart';

/// Driver-side filter for open loads. Empty fields don't filter.
class LoadFilter {
  final String pickupQuery;
  final String? vehicleType;

  /// Loads without a budget (negotiable) are excluded when this is set.
  final num? minBudget;

  const LoadFilter({this.pickupQuery = '', this.vehicleType, this.minBudget});

  static const none = LoadFilter();

  bool get isEmpty => pickupQuery.trim().isEmpty && vehicleType == null && minBudget == null;

  /// Number of sheet filters in use (the search box is shown separately).
  int get sheetFilterCount => (vehicleType != null ? 1 : 0) + (minBudget != null ? 1 : 0);

  LoadFilter copyWith({String? pickupQuery, String? Function()? vehicleType, num? Function()? minBudget}) => LoadFilter(
        pickupQuery: pickupQuery ?? this.pickupQuery,
        vehicleType: vehicleType != null ? vehicleType() : this.vehicleType,
        minBudget: minBudget != null ? minBudget() : this.minBudget,
      );

  bool matches(Load load) {
    final q = pickupQuery.trim().toLowerCase();
    if (q.isNotEmpty && !load.pickup.toLowerCase().contains(q)) return false;
    if (vehicleType != null && load.vehicleType != vehicleType) return false;
    if (minBudget != null && (load.budget == null || load.budget! < minBudget!)) return false;
    return true;
  }

  List<Load> apply(Iterable<Load> loads) => loads.where(matches).toList();
}
