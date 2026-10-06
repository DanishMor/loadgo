/// Pure-Dart fare engine. All money is integer paise; percentages are
/// applied in basis points and rounded half-up to the nearest paisa.
///
/// TODO(functions): the authoritative fare, payout and platform fee should be
/// computed server-side (Cloud Functions). Until then this is an estimate the
/// customer sees; Firestore rules only check its shape.
library;

import 'surge.dart';

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

  /// Fixed charge for each helper (labour) added to the booking.
  final int helperCharge;

  /// Hourly rental: price per package hour, km included per hour, and the
  /// charges beyond the package. [extraHourCharge] 0 means "same as hourly".
  final int rentalPerHour;
  final int rentalKmPerHour;
  final int extraKmCharge;
  final int extraHourCharge;

  /// Packers and movers: handling per item (units counted), per floor above
  /// the ground when there is no lift, and packing material + work per item.
  final int moversPerItem;
  final int moversPerFloor;
  final int packingPerItem;

  const PricingRule({
    required this.baseFare,
    required this.perKm,
    required this.minimumFare,
    this.loadingCharge = 0,
    this.unloadingCharge = 0,
    this.waitingPerHour = 0,
    this.perExtraStop = 0,
    this.helperCharge = 0,
    this.rentalPerHour = 0,
    this.rentalKmPerHour = 10,
    this.extraKmCharge = 0,
    this.extraHourCharge = 0,
    this.moversPerItem = 0,
    this.moversPerFloor = 0,
    this.packingPerItem = 0,
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
      helperCharge: v('helperCharge', fallback.helperCharge),
      rentalPerHour: v('rentalPerHour', fallback.rentalPerHour),
      rentalKmPerHour: v('rentalKmPerHour', fallback.rentalKmPerHour),
      extraKmCharge: v('extraKmCharge', fallback.extraKmCharge),
      extraHourCharge: v('extraHourCharge', fallback.extraHourCharge),
      moversPerItem: v('moversPerItem', fallback.moversPerItem),
      moversPerFloor: v('moversPerFloor', fallback.moversPerFloor),
      packingPerItem: v('packingPerItem', fallback.packingPerItem),
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
        'helperCharge': helperCharge,
        'rentalPerHour': rentalPerHour,
        'rentalKmPerHour': rentalKmPerHour,
        'extraKmCharge': extraKmCharge,
        'extraHourCharge': extraHourCharge,
        'moversPerItem': moversPerItem,
        'moversPerFloor': moversPerFloor,
        'packingPerItem': packingPerItem,
      };

  /// Charge for one extra started hour beyond a rental package.
  int get effectiveExtraHour => extraHourCharge > 0 ? extraHourCharge : rentalPerHour;
}

/// Hourly rental packages offered to customers.
const rentalHourOptions = [4, 8, 12];

/// Most helpers that can be added to one booking.
const maxHelpers = 4;

/// What a packers-and-movers request needs to be priced.
class MoversDetails {
  /// Item name -> units (for example sofa: 1, boxes: 20).
  final Map<String, int> items;

  /// Floor of the pickup home (0 = ground).
  final int floor;
  final bool hasLift;
  final bool packingNeeded;

  const MoversDetails({this.items = const {}, this.floor = 0, this.hasLift = true, this.packingNeeded = false});

  int get units => items.values.fold(0, (a, b) => a + b);

  Map<String, Object> toMap() => {
        'items': [for (final e in items.entries) {'name': e.key, 'qty': e.value}],
        'floor': floor,
        'hasLift': hasLift,
        'packing': packingNeeded,
      };

  factory MoversDetails.fromMap(Object? raw) {
    final m = raw is Map ? raw : const {};
    final items = <String, int>{};
    for (final e in (m['items'] as List?) ?? const []) {
      if (e is Map && e['name'] is String) items[e['name'] as String] = (e['qty'] as num?)?.toInt() ?? 1;
    }
    return MoversDetails(
      items: items,
      floor: (m['floor'] as num?)?.toInt() ?? 0,
      hasLift: m['hasLift'] != false,
      packingNeeded: m['packing'] == true,
    );
  }

  /// One item per line, "name" or "name x3" / "name 3"; blank lines ignored.
  /// Returns null if a line has a bad quantity.
  static Map<String, int>? parseItems(String text) {
    final out = <String, int>{};
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final m = RegExp(r'^(.*?)(?:\s*[xX*]?\s*(\d+))?$').firstMatch(line)!;
      final name = (m.group(1) ?? '').trim();
      final qty = m.group(2) == null ? 1 : int.parse(m.group(2)!);
      if (name.isEmpty || qty < 1 || qty > 99) return null;
      out[name] = (out[name] ?? 0) + qty;
    }
    return out;
  }
}

/// Config-driven cancellation charge (recorded only; no money moves).
class CancellationPolicy {
  /// Minutes after acceptance during which cancelling is free.
  final int freeMinutes;

  /// Percent of the estimated fare, clamped to [minCharge]..[maxCharge].
  final num chargePercent;
  final int minCharge;
  final int maxCharge;

  /// For scheduled bookings: cancelling is free until this many hours before
  /// the pickup time.
  final int scheduledFreeHours;

  const CancellationPolicy({
    this.freeMinutes = 15,
    this.chargePercent = 10,
    this.minCharge = 5000,
    this.maxCharge = 100000,
    this.scheduledFreeHours = 2,
  });

  factory CancellationPolicy.fromMap(Map<String, dynamic>? m) {
    const d = CancellationPolicy();
    if (m == null) return d;
    return CancellationPolicy(
      freeMinutes: (m['freeMinutes'] as num?)?.round() ?? d.freeMinutes,
      chargePercent: m['chargePercent'] as num? ?? d.chargePercent,
      minCharge: (m['minCharge'] as num?)?.round() ?? d.minCharge,
      maxCharge: (m['maxCharge'] as num?)?.round() ?? d.maxCharge,
      scheduledFreeHours: (m['scheduledFreeHours'] as num?)?.round() ?? d.scheduledFreeHours,
    );
  }

  Map<String, num> toMap() =>
      {
        'freeMinutes': freeMinutes,
        'chargePercent': chargePercent,
        'minCharge': minCharge,
        'maxCharge': maxCharge,
        'scheduledFreeHours': scheduledFreeHours,
      };

  /// Charge in paise for cancelling [elapsed] after acceptance on a trip
  /// worth [farePaise] (null = no estimate, the minimum applies).
  int chargeFor({required Duration elapsed, int? farePaise}) {
    if (elapsed.inMinutes < freeMinutes) return 0;
    return _charge(farePaise);
  }

  /// Charge for cancelling a scheduled booking: free until
  /// [scheduledFreeHours] before the pickup, the normal charge after.
  int chargeForScheduled({required DateTime now, required DateTime scheduledAt, int? farePaise}) =>
      now.isAfter(scheduledAt.subtract(Duration(hours: scheduledFreeHours))) ? _charge(farePaise) : 0;

  int _charge(int? farePaise) {
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

  /// Helpers (labour), hourly rental package, kilometres/hours beyond the
  /// package, and packers-and-movers lines. All 0 on a plain freight fare.
  final int helperCharge;
  final int rentalCharge;
  final int extraKmCharge;
  final int extraHourCharge;
  final int itemHandlingCharge;
  final int floorCharge;
  final int packingCharge;

  /// Top-up so the trip fare reaches the minimum fare (0 if not needed).
  final int minimumFareAdjustment;

  /// Peak/night/festival surge on the base freight (0 when off) with the
  /// percent applied and its [SurgeKind].
  final int surgeCharge;
  final int surgePercent;
  final String surgeKind;
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
    this.helperCharge = 0,
    this.rentalCharge = 0,
    this.extraKmCharge = 0,
    this.extraHourCharge = 0,
    this.itemHandlingCharge = 0,
    this.floorCharge = 0,
    this.packingCharge = 0,
    required this.minimumFareAdjustment,
    this.surgeCharge = 0,
    this.surgePercent = 0,
    this.surgeKind = SurgeKind.none,
    required this.platformFee,
    required this.gst,
    required this.platformFeePercent,
    required this.gstPercent,
  });

  /// What the trip itself costs (driver side), before platform fee and GST.
  int get tripFare =>
      baseFare + distanceCharge + loadingCharge + unloadingCharge + waitingCharge + extraStopCharge + minimumFareAdjustment +
      helperCharge + rentalCharge + extraKmCharge + extraHourCharge + itemHandlingCharge + floorCharge + packingCharge + surgeCharge;

  int get total => tripFare + platformFee + gst;

  Map<String, Object> toMap() => {
        'distanceKm': distanceKm,
        'baseFare': baseFare,
        'distanceCharge': distanceCharge,
        'loadingCharge': loadingCharge,
        'unloadingCharge': unloadingCharge,
        'waitingCharge': waitingCharge,
        'extraStopCharge': extraStopCharge,
        'helperCharge': helperCharge,
        'rentalCharge': rentalCharge,
        'extraKmCharge': extraKmCharge,
        'extraHourCharge': extraHourCharge,
        'itemHandlingCharge': itemHandlingCharge,
        'floorCharge': floorCharge,
        'packingCharge': packingCharge,
        'minimumFareAdjustment': minimumFareAdjustment,
        if (surgeCharge > 0) ...{'surgeCharge': surgeCharge, 'surgePercent': surgePercent, 'surgeKind': surgeKind},
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
      helperCharge: v('helperCharge'),
      rentalCharge: v('rentalCharge'),
      extraKmCharge: v('extraKmCharge'),
      extraHourCharge: v('extraHourCharge'),
      itemHandlingCharge: v('itemHandlingCharge'),
      floorCharge: v('floorCharge'),
      packingCharge: v('packingCharge'),
      minimumFareAdjustment: v('minimumFareAdjustment'),
      surgeCharge: v('surgeCharge'),
      surgePercent: v('surgePercent'),
      surgeKind: m['surgeKind'] is String ? m['surgeKind'] as String : SurgeKind.none,
      platformFee: v('platformFee'),
      gst: v('gst'),
      platformFeePercent: m['platformFeePercent'] as num? ?? 0,
      gstPercent: m['gstPercent'] as num? ?? 0,
    );
  }
}

class FareCalculator {
  FareCalculator._();

  /// Waiting charge for [minutes] at the points: the first [freeMinutes] are
  /// free, then every started hour costs `waitingPerHour`.
  static int detentionCharge(PricingRule rule, int minutes, {int freeMinutes = 60}) {
    final over = minutes - freeMinutes;
    return over <= 0 ? 0 : rule.waitingPerHour * ((over + 59) ~/ 60);
  }

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
    int helpers = 0,
    MoversDetails? movers,
    SurgeQuote surge = SurgeQuote.none,
  }) {
    if (distanceKm < 0) throw ArgumentError.value(distanceKm, 'distanceKm');
    if (helpers < 0 || helpers > maxHelpers) throw ArgumentError.value(helpers, 'helpers');
    final base = rule.baseFare;
    final distance = rule.perKm * distanceKm;
    final load = loading ? rule.loadingCharge : 0;
    final unload = unloading ? rule.unloadingCharge : 0;
    final waiting = rule.waitingPerHour * ((waitingMinutes + 59) ~/ 60);
    final stops = rule.perExtraStop * (extraStops < 0 ? 0 : extraStops);
    final helper = rule.helperCharge * helpers;
    final handling = movers == null ? 0 : rule.moversPerItem * movers.units;
    // Climbing floors only costs extra when there is no lift.
    final floors = movers == null || movers.hasLift ? 0 : rule.moversPerFloor * (movers.floor < 0 ? 0 : movers.floor);
    final packing = movers == null || !movers.packingNeeded ? 0 : rule.packingPerItem * movers.units;
    final sum = base + distance + load + unload + waiting + stops;
    final topUp = sum < rule.minimumFare ? rule.minimumFare - sum : 0;
    // Surge applies to the base freight only (not helpers, handling or fees).
    final surgeCharge = surge.active ? _pct(sum + topUp, surge.percent) : 0;
    final trip = sum + topUp + surgeCharge + helper + handling + floors + packing;
    final fee = _pct(trip, platformFeePercent);
    final gst = _pct(trip + fee, gstPercent);
    return FareBreakdown(
      helperCharge: helper,
      itemHandlingCharge: handling,
      floorCharge: floors,
      packingCharge: packing,
      distanceKm: distanceKm,
      baseFare: base,
      distanceCharge: distance,
      loadingCharge: load,
      unloadingCharge: unload,
      waitingCharge: waiting,
      extraStopCharge: stops,
      minimumFareAdjustment: topUp,
      surgeCharge: surgeCharge,
      surgePercent: surgeCharge > 0 ? surge.percent : 0,
      surgeKind: surgeCharge > 0 ? surge.kind : SurgeKind.none,
      platformFee: fee,
      gst: gst,
      platformFeePercent: platformFeePercent,
      gstPercent: gstPercent,
    );
  }

  /// Hourly rental: the package price for [hours] (4, 8 or 12), plus
  /// [helpers]. Kilometres beyond `hours x rentalKmPerHour` and started hours
  /// beyond the package are billed at the extra rates; pass the actual
  /// [usedKm] / [usedMinutes] once the trip is over (they default to the
  /// package, so a quote has no extras).
  static FareBreakdown calculateRental({
    required PricingRule rule,
    required int hours,
    num platformFeePercent = 0,
    num gstPercent = 0,
    int helpers = 0,
    int? usedKm,
    int? usedMinutes,
  }) {
    if (!rentalHourOptions.contains(hours)) throw ArgumentError.value(hours, 'hours');
    if (helpers < 0 || helpers > maxHelpers) throw ArgumentError.value(helpers, 'helpers');
    final includedKm = hours * rule.rentalKmPerHour;
    final overKm = usedKm == null || usedKm <= includedKm ? 0 : usedKm - includedKm;
    final overMinutes = usedMinutes == null || usedMinutes <= hours * 60 ? 0 : usedMinutes - hours * 60;
    final overHours = (overMinutes + 59) ~/ 60;
    final package = rule.rentalPerHour * hours;
    final extraKm = overKm * rule.extraKmCharge;
    final extraHours = overHours * rule.effectiveExtraHour;
    final helper = rule.helperCharge * helpers;
    final trip = package + extraKm + extraHours + helper;
    final fee = _pct(trip, platformFeePercent);
    final gst = _pct(trip + fee, gstPercent);
    return FareBreakdown(
      distanceKm: usedKm ?? includedKm,
      baseFare: 0,
      distanceCharge: 0,
      loadingCharge: 0,
      unloadingCharge: 0,
      waitingCharge: 0,
      extraStopCharge: 0,
      rentalCharge: package,
      extraKmCharge: extraKm,
      extraHourCharge: extraHours,
      helperCharge: helper,
      minimumFareAdjustment: 0,
      platformFee: fee,
      gst: gst,
      platformFeePercent: platformFeePercent,
      gstPercent: gstPercent,
    );
  }
}
