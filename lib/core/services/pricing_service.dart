import 'package:flutter/foundation.dart';

import '../pricing/cities.dart';
import '../pricing/fare_calculator.dart';
import '../pricing/pricing_config.dart';
import 'backend.dart';
import 'vehicle_type_service.dart';

/// Where a fare estimate's distance came from.
class DistanceSource {
  DistanceSource._();
  static const cities = 'cities';
  static const manual = 'manual';
}

/// Reads `config/pricing` (admin-written) with [defaultPricing] as fallback
/// and turns a route + vehicle type into a [FareBreakdown].
class PricingService {
  PricingService._();

  static final ValueNotifier<PricingConfig> notifier = ValueNotifier(defaultPricing);

  static PricingConfig get config => notifier.value;

  static Future<void> refresh() async {
    try {
      final snap = await Backend.db.collection('config').doc('pricing').get();
      notifier.value = PricingConfig.fromMap(snap.data());
    } catch (_) {
      // Keep the current config when offline / signed out.
    }
  }

  /// Admin only (enforced by rules).
  static Future<void> save(PricingConfig c) => Backend.db.collection('config').doc('pricing').set(c.toMap());

  /// Estimated road km between the cities named in [from] and [to], or null
  /// when either place is not in the offline table.
  static int? estimateKm(String from, String to) {
    final a = findCity(from);
    final b = findCity(to);
    if (a == null || b == null) return null;
    return roadKmBetween(a, b, roadFactor: config.roadFactor);
  }

  static FareBreakdown quote({
    required String vehicleType,
    required int distanceKm,
    int extraStops = 0,
    int waitingMinutes = 0,
  }) {
    final category = VehicleTypeService.byId(vehicleType)?.category ?? 'lcv';
    final c = config;
    return FareCalculator.calculate(
      rule: c.ruleFor(vehicleType, category),
      distanceKm: distanceKm,
      platformFeePercent: c.platformFeePercent,
      gstPercent: c.gstPercent,
      extraStops: extraStops,
      waitingMinutes: waitingMinutes,
    );
  }

  @visibleForTesting
  static void reset() => notifier.value = defaultPricing;
}
