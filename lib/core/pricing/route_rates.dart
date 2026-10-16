import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../features/features.dart';
import '../l10n/l10n.dart';
import '../services/backend.dart';
import '../theme/design_tokens.dart';
import '../widgets/common.dart' show formatPaise;
import '../widgets/feature_gate.dart';
import 'cities.dart';

/// The usual price of a route from finished trips (G20): the middle half of the last amounts, in paise.
class RateRange {
  final int low;
  final int mid;
  final int high;
  final int trips;
  const RateRange(this.low, this.mid, this.high, this.trips);
}

class RouteRates {
  RouteRates._();

  /// Fewer finished trips than this and no number is shown (one odd trip would pass for "usual").
  static const minTrips = 5;

  static String _slug(String s) {
    final t = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    return t.length > 24 ? t.substring(0, 24) : t;
  }

  /// The same key the server uses (`functions/src/rates.js`), or null when a place is not in the city table.
  static String? keyFor(String pickup, String drop, String vehicleType) {
    final a = findCity(pickup);
    final b = findCity(drop);
    final v = _slug(vehicleType);
    if (a == null || b == null || v.isEmpty || a.name == b.name) return null;
    return '${_slug(a.name)}_${_slug(b.name)}_$v';
  }

  /// 25th, 50th and 75th percentile (nearest rank) of the amounts, rounded to whole ten rupees. Null under [minTrips]
  /// or when the document is damaged.
  static RateRange? fromDoc(Map<String, dynamic>? d) {
    final r = d?['recent'];
    if (r is! List) return null;
    final amounts = [for (final v in r) if (v is int && v > 0) v]..sort();
    if (amounts.length < minTrips) return null;
    int at(double p) => amounts[(p * amounts.length).ceil().clamp(1, amounts.length) - 1];
    int round10(int paise) => ((paise + 500) ~/ 1000) * 1000;
    final n = d?['n'];
    return RateRange(round10(at(0.25)), round10(at(0.5)), round10(at(0.75)), n is int && n >= amounts.length ? n : amounts.length);
  }

  static final Map<String, Future<RateRange?>> _cache = {};

  /// One read per route and truck type per run; any problem is "no range".
  static Future<RateRange?> fetch(String pickup, String drop, String vehicleType) {
    final key = keyFor(pickup, drop, vehicleType);
    if (key == null) return Future.value(null);
    return _cache.putIfAbsent(key, () async {
      try {
        final snap = await Backend.db.collection('route_rates').doc(key).get();
        return fromDoc(snap.data());
      } on FirebaseException {
        return null;
      } catch (_) {
        return null;
      }
    });
  }

  static void clearCache() => _cache.clear();
}

/// "Usual price on this route: ₹42,000 to ₹48,000 (30 trips)" under the estimate when a post-load form is filled.
/// Behind `rateRange` (OFF). Shows nothing without enough trips, without a server or with the switch off.
class RateRangeLine extends StatelessWidget {
  final String pickup;
  final String drop;
  final String vehicleType;
  final Future<RateRange?>? source;

  const RateRangeLine({super.key, required this.pickup, required this.drop, required this.vehicleType, this.source});

  @override
  Widget build(BuildContext context) {
    return FeatureGate(
      featureKey: FeatureKey.rateRange,
      child: FutureBuilder<RateRange?>(
        key: ValueKey('rate_${pickup}_${drop}_$vehicleType'),
        future: source ?? RouteRates.fetch(pickup, drop, vehicleType),
        builder: (context, snap) {
          final r = snap.data;
          if (snap.hasError || r == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: DsSpace.s2),
            child: Text(
              trf(context, 'rrUsual', {'low': formatPaise(r.low), 'high': formatPaise(r.high), 'n': r.trips}),
              key: const ValueKey('rateRangeLine'),
              style: DsType.caption.copyWith(color: context.ds.textMuted),
            ),
          );
        },
      ),
    );
  }
}
