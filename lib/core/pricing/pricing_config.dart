import 'fare_calculator.dart';

/// `config/pricing`: rate cards per vehicle category with optional
/// per-vehicle-type overrides, plus fee/tax/cancellation settings.
class PricingConfig {
  /// Keyed by `VehicleTypeInfo.category` (two_wheeler, three_wheeler, lcv, hcv, container, trailer).
  final Map<String, PricingRule> categories;

  /// Keyed by vehicle type id; wins over [categories].
  final Map<String, PricingRule> types;
  final num platformFeePercent;
  final num gstPercent;
  final double roadFactor;
  final CancellationPolicy cancellation;

  const PricingConfig({
    required this.categories,
    this.types = const {},
    this.platformFeePercent = 5,
    this.gstPercent = 5,
    this.roadFactor = 1.25,
    this.cancellation = const CancellationPolicy(),
  });

  PricingRule ruleFor(String vehicleTypeId, String category) =>
      types[vehicleTypeId] ?? categories[category] ?? categories['lcv'] ?? defaultPricing.categories['lcv']!;

  factory PricingConfig.fromMap(Map<String, dynamic>? m) {
    if (m == null) return defaultPricing;
    Map<String, PricingRule> rules(Object? raw, Map<String, PricingRule> fallback) {
      final out = Map<String, PricingRule>.of(fallback);
      if (raw is Map) {
        for (final e in raw.entries) {
          if (e.value is Map) {
            final base = fallback[e.key] ?? defaultPricing.categories['lcv']!;
            out[e.key as String] = PricingRule.fromMap(Map<String, dynamic>.from(e.value as Map), base);
          }
        }
      }
      return out;
    }

    return PricingConfig(
      categories: rules(m['categories'], defaultPricing.categories),
      types: rules(m['types'], const {}),
      platformFeePercent: m['platformFeePercent'] as num? ?? defaultPricing.platformFeePercent,
      gstPercent: m['gstPercent'] as num? ?? defaultPricing.gstPercent,
      roadFactor: (m['roadFactor'] as num?)?.toDouble() ?? defaultPricing.roadFactor,
      cancellation: CancellationPolicy.fromMap(m['cancellation'] as Map<String, dynamic>?),
    );
  }

  Map<String, dynamic> toMap() => {
        'categories': {for (final e in categories.entries) e.key: e.value.toMap()},
        'types': {for (final e in types.entries) e.key: e.value.toMap()},
        'platformFeePercent': platformFeePercent,
        'gstPercent': gstPercent,
        'roadFactor': roadFactor,
        'cancellation': cancellation.toMap(),
      };
}

/// Built-in rate cards (paise), used until an admin saves `config/pricing`.
const PricingConfig defaultPricing = PricingConfig(categories: {
  'two_wheeler': PricingRule(baseFare: 3000, perKm: 800, minimumFare: 5000, waitingPerHour: 6000, perExtraStop: 2000),
  'three_wheeler': PricingRule(
      baseFare: 15000, perKm: 1600, minimumFare: 25000, loadingCharge: 5000, unloadingCharge: 5000,
      waitingPerHour: 15000, perExtraStop: 5000),
  'lcv': PricingRule(
      baseFare: 50000, perKm: 2800, minimumFare: 80000, loadingCharge: 20000, unloadingCharge: 20000,
      waitingPerHour: 30000, perExtraStop: 15000),
  'hcv': PricingRule(
      baseFare: 150000, perKm: 5500, minimumFare: 300000, loadingCharge: 50000, unloadingCharge: 50000,
      waitingPerHour: 60000, perExtraStop: 40000),
  'container': PricingRule(
      baseFare: 250000, perKm: 7000, minimumFare: 500000, loadingCharge: 100000, unloadingCharge: 100000,
      waitingPerHour: 100000, perExtraStop: 60000),
  'trailer': PricingRule(
      baseFare: 400000, perKm: 9500, minimumFare: 800000, loadingCharge: 150000, unloadingCharge: 150000,
      waitingPerHour: 150000, perExtraStop: 80000),
});
