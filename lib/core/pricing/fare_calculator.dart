/// Pure-Dart fare engine. All money is integer paise; percentages are
/// applied in basis points and rounded half-up to the nearest paisa.
///
/// TODO(functions): the authoritative fare, payout and platform fee should be
/// computed server-side (Cloud Functions). Until then this is an estimate the
/// customer sees; Firestore rules only check its shape.
library;

int _pct(int amount, num percent) => (amount * (percent * 100).round() / 10000).round();

/// Rate card for one vehicle type (or category).
class PricingRule {
  final int baseFare;
  final int perKm;
  final int minimumFare;
  final int loadingCharge;
  final int unloadingCharge;
  final int waitingPerHour;

  /// Extra pickup/drop stop beyond the first of each.
  final int perExtraStop;

  const PricingRule({
    required this.baseFare,
    required this.perKm,
    required this.minimumFare,
    this.loadingCharge = 0,
    this.unloadingCharge = 0,
    this.waitingPerHour = 0,
    this.perExtraStop = 0,
  });

  factory PricingRule.fromMap(Map<String, dynamic> m, PricingRule fallback) {
    int v(String k, int f) => (m[k] as num?)?.round() ?? f;
    return PricingRule(
      baseFare: v('baseFare', fallback.baseFare),
      perKm: v('perKm', fallback.perKm),
      minimumFare: v('minimumFare', fallback.minimumFare),
      loadingCharge: v('loadingCharge', fallback.loadingCharge),
      unloadingCharge: v('unloadingCharge', fallback.unloadingCharge),
      waitingPerHour: v('waitingPerHour', fallback.waitingPerHour),
      perExtraStop: v('perExtraStop', fallback.perExtraStop),
    );
  }

  Map<String, int> toMap() => {
        'baseFare': baseFare,
        'perKm': perKm,
        'minimumFare': minimumFare,
        'loadingCharge': loadingCharge,
        'unloadingCharge': unloadingCharge,
        'waitingPerHour': waitingPerHour,
        'perExtraStop': perExtraStop,
      };
}

/// Config-driven cancellation charge (recorded only; no money moves).
class CancellationPolicy {
  /// Minutes after acceptance during which cancelling is free.
  final int freeMinutes;

  /// Percent of the estimated fare, clamped to [minCharge]..[maxCharge].
  final num chargePercent;
  final int minCharge;
  final int maxCharge;

  const CancellationPolicy({this.freeMinutes = 15, this.chargePercent = 10, this.minCharge = 5000, this.maxCharge = 100000});

  factory CancellationPolicy.fromMap(Map<String, dynamic>? m) {
    const d = CancellationPolicy();
    if (m == null) return d;
    return CancellationPolicy(
      freeMinutes: (m['freeMinutes'] as num?)?.round() ?? d.freeMinutes,
      chargePercent: m['chargePercent'] as num? ?? d.chargePercent,
      minCharge: (m['minCharge'] as num?)?.round() ?? d.minCharge,
      maxCharge: (m['maxCharge'] as num?)?.round() ?? d.maxCharge,
    );
  }

  Map<String, num> toMap() =>
      {'freeMinutes': freeMinutes, 'chargePercent': chargePercent, 'minCharge': minCharge, 'maxCharge': maxCharge};

  /// Charge in paise for cancelling [elapsed] after acceptance on a trip
  /// worth [farePaise] (null = no estimate, the minimum applies).
  int chargeFor({required Duration elapsed, int? farePaise}) {
    if (elapsed.inMinutes < freeMinutes) return 0;
    final raw = farePaise == null ? minCharge : _pct(farePaise, chargePercent);
    return raw.clamp(minCharge, maxCharge < minCharge ? minCharge : maxCharge);
  }
}

class FareBreakdown {
  final int distanceKm;
  final int baseFare;
  final int distanceCharge;
  final int loadingCharge;
  final int unloadingCharge;
  final int waitingCharge;
  final int extraStopCharge;

  /// Top-up so the trip fare reaches the minimum fare (0 if not needed).
  final int minimumFareAdjustment;
  final int platformFee;
  final int gst;
  final num platformFeePercent;
  final num gstPercent;

  const FareBreakdown({
    required this.distanceKm,
    required this.baseFare,
    required this.distanceCharge,
    required this.loadingCharge,
    required this.unloadingCharge,
    required this.waitingCharge,
    required this.extraStopCharge,
    required this.minimumFareAdjustment,
    required this.platformFee,
    required this.gst,
    required this.platformFeePercent,
    required this.gstPercent,
  });

  /// What the trip itself costs (driver side), before platform fee and GST.
  int get tripFare =>
      baseFare + distanceCharge + loadingCharge + unloadingCharge + waitingCharge + extraStopCharge + minimumFareAdjustment;

  int get total => tripFare + platformFee + gst;

  Map<String, num> toMap() => {
        'distanceKm': distanceKm,
        'baseFare': baseFare,
        'distanceCharge': distanceCharge,
        'loadingCharge': loadingCharge,
        'unloadingCharge': unloadingCharge,
        'waitingCharge': waitingCharge,
        'extraStopCharge': extraStopCharge,
        'minimumFareAdjustment': minimumFareAdjustment,
        'platformFee': platformFee,
        'gst': gst,
        'platformFeePercent': platformFeePercent,
        'gstPercent': gstPercent,
        'tripFare': tripFare,
        'total': total,
      };

  factory FareBreakdown.fromMap(Map<String, dynamic> m) {
    int v(String k) => (m[k] as num?)?.round() ?? 0;
    return FareBreakdown(
      distanceKm: v('distanceKm'),
      baseFare: v('baseFare'),
      distanceCharge: v('distanceCharge'),
      loadingCharge: v('loadingCharge'),
      unloadingCharge: v('unloadingCharge'),
      waitingCharge: v('waitingCharge'),
      extraStopCharge: v('extraStopCharge'),
      minimumFareAdjustment: v('minimumFareAdjustment'),
      platformFee: v('platformFee'),
      gst: v('gst'),
      platformFeePercent: m['platformFeePercent'] as num? ?? 0,
      gstPercent: m['gstPercent'] as num? ?? 0,
    );
  }
}

class FareCalculator {
  FareCalculator._();

  /// Fare for [distanceKm] with [rule]. Waiting is billed per started hour
  /// from [waitingMinutes]. Platform fee is a percent of the trip fare; GST is
  /// charged on trip fare + platform fee.
  static FareBreakdown calculate({
    required PricingRule rule,
    required int distanceKm,
    num platformFeePercent = 0,
    num gstPercent = 0,
    bool loading = true,
    bool unloading = true,
    int waitingMinutes = 0,
    int extraStops = 0,
  }) {
    if (distanceKm < 0) throw ArgumentError.value(distanceKm, 'distanceKm');
    final base = rule.baseFare;
    final distance = rule.perKm * distanceKm;
    final load = loading ? rule.loadingCharge : 0;
    final unload = unloading ? rule.unloadingCharge : 0;
    final waiting = rule.waitingPerHour * ((waitingMinutes + 59) ~/ 60);
    final stops = rule.perExtraStop * (extraStops < 0 ? 0 : extraStops);
    final sum = base + distance + load + unload + waiting + stops;
    final topUp = sum < rule.minimumFare ? rule.minimumFare - sum : 0;
    final trip = sum + topUp;
    final fee = _pct(trip, platformFeePercent);
    final gst = _pct(trip + fee, gstPercent);
    return FareBreakdown(
      distanceKm: distanceKm,
      baseFare: base,
      distanceCharge: distance,
      loadingCharge: load,
      unloadingCharge: unload,
      waitingCharge: waiting,
      extraStopCharge: stops,
      minimumFareAdjustment: topUp,
      platformFee: fee,
      gst: gst,
      platformFeePercent: platformFeePercent,
      gstPercent: gstPercent,
    );
  }
}
