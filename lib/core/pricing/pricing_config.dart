import '../scheduling/schedule.dart';
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

  /// Recorded on the driver's ledger when they confirm payment received.
  final num commissionPercent;

  /// Minutes of waiting at the points that are free before detention is charged.
  final int detentionFreeMinutes;

  /// Advance booking limits and activation lead time.
  final ScheduleRules schedule;

  /// Commission for drivers on the Pro plan.
  final num proCommissionPercent;
  final double roadFactor;
  final CancellationPolicy cancellation;

  const PricingConfig({
    required this.categories,
    this.types = const {},
    this.platformFeePercent = 5,
    this.gstPercent = 5,
    this.commissionPercent = 5,
    this.proCommissionPercent = 2,
    this.detentionFreeMinutes = 60,
    this.schedule = const ScheduleRules(),
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
      commissionPercent: m['commissionPercent'] as num? ?? defaultPricing.commissionPercent,
      proCommissionPercent: m['proCommissionPercent'] as num? ?? defaultPricing.proCommissionPercent,
      detentionFreeMinutes: (m['detentionFreeMinutes'] as num?)?.round() ?? defaultPricing.detentionFreeMinutes,
      schedule: ScheduleRules.fromMap(
        m['schedule'] as Map<String, dynamic>?,
        freeCancelHours: ((m['cancellation'] as Map?)?['scheduledFreeHours'] as num?)?.round() ?? 2,
      ),
      roadFactor: (m['roadFactor'] as num?)?.toDouble() ?? defaultPricing.roadFactor,
      cancellation: CancellationPolicy.fromMap(m['cancellation'] as Map<String, dynamic>?),
    );
  }

  Map<String, dynamic> toMap() => {
        'categories': {for (final e in categories.entries) e.key: e.value.toMap()},
        'types': {for (final e in types.entries) e.key: e.value.toMap()},
        'platformFeePercent': platformFeePercent,
        'gstPercent': gstPercent,
        'commissionPercent': commissionPercent,
        'proCommissionPercent': proCommissionPercent,
        'detentionFreeMinutes': detentionFreeMinutes,
        'schedule': schedule.toMap(),
        'roadFactor': roadFactor,
        'cancellation': cancellation.toMap(),
      };
}

/// Built-in rate cards (paise), used until an admin saves `config/pricing`.
const PricingConfig defaultPricing = PricingConfig(categories: {
  'two_wheeler': PricingRule(
      baseFare: 3000, perKm: 800, minimumFare: 5000, waitingPerHour: 6000, perExtraStop: 2000,
      helperCharge: 15000, rentalPerHour: 12000, rentalKmPerHour: 8, extraKmCharge: 900, moversPerItem: 500, moversPerFloor: 500, packingPerItem: 300),
  'three_wheeler': PricingRule(
      baseFare: 15000, perKm: 1600, minimumFare: 25000, loadingCharge: 5000, unloadingCharge: 5000,
      waitingPerHour: 15000, perExtraStop: 5000,
      helperCharge: 20000, rentalPerHour: 30000, rentalKmPerHour: 10, extraKmCharge: 1800, moversPerItem: 1500, moversPerFloor: 2000, packingPerItem: 800),
  'lcv': PricingRule(
      baseFare: 50000, perKm: 2800, minimumFare: 80000, loadingCharge: 20000, unloadingCharge: 20000,
      waitingPerHour: 30000, perExtraStop: 15000,
      helperCharge: 30000, rentalPerHour: 60000, rentalKmPerHour: 10, extraKmCharge: 3000, moversPerItem: 2500, moversPerFloor: 3000, packingPerItem: 1500),
  'hcv': PricingRule(
      baseFare: 150000, perKm: 5500, minimumFare: 300000, loadingCharge: 50000, unloadingCharge: 50000,
      waitingPerHour: 60000, perExtraStop: 40000,
      helperCharge: 40000, rentalPerHour: 120000, rentalKmPerHour: 10, extraKmCharge: 6000, moversPerItem: 4000, moversPerFloor: 4000, packingPerItem: 2500),
  'container': PricingRule(
      baseFare: 250000, perKm: 7000, minimumFare: 500000, loadingCharge: 100000, unloadingCharge: 100000,
      waitingPerHour: 100000, perExtraStop: 60000,
      helperCharge: 50000, rentalPerHour: 200000, rentalKmPerHour: 10, extraKmCharge: 8000),
  'trailer': PricingRule(
      baseFare: 400000, perKm: 9500, minimumFare: 800000, loadingCharge: 150000, unloadingCharge: 150000,
      waitingPerHour: 150000, perExtraStop: 80000,
      helperCharge: 50000, rentalPerHour: 300000, rentalKmPerHour: 10, extraKmCharge: 10000),
});
