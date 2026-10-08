import 'package:flutter/foundation.dart';

import '../pricing/cities.dart';
import '../pricing/fare_calculator.dart';
import '../pricing/pricing_config.dart';
import '../pricing/surge.dart';
import 'backend.dart';
import 'audit_service.dart';
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
  static Future<void> save(PricingConfig c) {
    final batch = Backend.db.batch();
    batch.set(Backend.db.collection('config').doc('pricing'), c.toMap());
    AuditService.inBatch(batch, AuditType.configChange, targetId: 'pricing', data: {'doc': 'pricing', 'changedKeys': const ['pricing']});
    return batch.commit();
  }

  /// Estimated road km between the cities named in [from] and [to], or null
  /// when either place is not in the offline table.
  static int? estimateKm(String from, String to) {
    final a = findCity(from);
    final b = findCity(to);
    if (a == null || b == null) return null;
    return roadKmBetween(a, b, roadFactor: config.roadFactor);
  }

  /// Road km along [places] (leg by leg), or null if any place is unknown.
  static int? estimateRouteKm(List<String> places) {
    if (places.length < 2) return null;
    var total = 0;
    for (var i = 0; i + 1 < places.length; i++) {
      final km = estimateKm(places[i], places[i + 1]);
      if (km == null) return null;
      total += km;
    }
    return total;
  }

  static FareBreakdown quote({
    required String vehicleType,
    required int distanceKm,
    int extraStops = 0,
    int waitingMinutes = 0,
    int helpers = 0,
    MoversDetails? movers,

    /// Pickup moment; surge (when enabled) is looked up at this time.
    DateTime? at,
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
      helpers: helpers,
      movers: movers,
      surge: at == null ? SurgeQuote.none : SurgeCalculator.at(at, c.surge),
    );
  }

  /// Hourly rental package quote ([hours] 4, 8 or 12). Pass [usedKm] /
  /// [usedMinutes] after the trip to bill extras.
  static FareBreakdown quoteRental({
    required String vehicleType,
    required int hours,
    int helpers = 0,
    int? usedKm,
    int? usedMinutes,
  }) {
    final category = VehicleTypeService.byId(vehicleType)?.category ?? 'lcv';
    final c = config;
    return FareCalculator.calculateRental(
      rule: c.ruleFor(vehicleType, category),
      hours: hours,
      platformFeePercent: c.platformFeePercent,
      gstPercent: c.gstPercent,
      helpers: helpers,
      usedKm: usedKm,
      usedMinutes: usedMinutes,
    );
  }

  /// Km included in a rental package for [vehicleType].
  static int rentalIncludedKm(String vehicleType, int hours) {
    final category = VehicleTypeService.byId(vehicleType)?.category ?? 'lcv';
    return hours * config.ruleFor(vehicleType, category).rentalKmPerHour;
  }

  @visibleForTesting
  static void reset() => notifier.value = defaultPricing;
}
