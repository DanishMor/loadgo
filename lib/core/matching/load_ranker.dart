import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/logistics.dart';
import '../models/load.dart';
import '../models/vehicle.dart';
import '../pricing/cities.dart';
import 'nearest.dart';

/// Why a load was recommended. Shown as chips on the driver's card.
enum MatchReason { nearPickup, returnLoad, favouriteRoute, bestFit, onYourRoute }

/// A route the driver saved (city names as typed).
class FavouriteRoute {
  final String id;
  final String pickup;
  final String drop;

  const FavouriteRoute({required this.id, required this.pickup, required this.drop});

  /// Stable id so saving the same route twice overwrites.
  static String idFor(String pickup, String drop) {
    final a = findCity(pickup)?.name ?? pickup.trim().toLowerCase();
    final b = findCity(drop)?.name ?? drop.trim().toLowerCase();
    return '${a}__$b'.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]+'), '-');
  }

  bool matches(Load load) => _sameCity(pickup, load.pickup) && _sameCity(drop, load.drop);
}

bool _sameCity(String a, String b) {
  final ca = findCity(a), cb = findCity(b);
  if (ca != null && cb != null) return ca.name == cb.name;
  return a.trim().toLowerCase() == b.trim().toLowerCase();
}

/// Where the driver is going next. Free text places matched against the
/// offline city table; [date] is only shown, not used for ranking.
class PlannedRoute {
  final String from;
  final String to;
  final DateTime? date;

  const PlannedRoute({required this.from, required this.to, this.date});

  /// A load is on the route when its pickup is within [radiusKm] of [from]
  /// and its drop within [radiusKm] of [to] (same city counts).
  static const radiusKm = 100.0;

  bool fits(Load load) {
    final a = findCity(from), b = findCity(to), p = findCity(load.pickup), d = findCity(load.drop);
    if (a == null || b == null || p == null || d == null) return false;
    return haversineKm(a.lat, a.lng, p.lat, p.lng) <= radiusKm && haversineKm(b.lat, b.lng, d.lat, d.lng) <= radiusKm;
  }

  factory PlannedRoute.fromMap(Map<dynamic, dynamic> m) => PlannedRoute(
        from: m['from']?.toString() ?? '',
        to: m['to']?.toString() ?? '',
        date: (m['date'] as Timestamp?)?.toDate(),
      );

  Map<String, Object> toMap() => {'from': from.trim(), 'to': to.trim(), if (date != null) 'date': Timestamp.fromDate(date!)};

  static PlannedRoute? fromUser(Map<String, dynamic>? user) {
    final m = user?['plannedRoute'];
    return m is Map && (m['from']?.toString().isNotEmpty ?? false) && (m['to']?.toString().isNotEmpty ?? false) ? PlannedRoute.fromMap(m) : null;
  }
}

/// What the ranker knows about the driver.
class DriverContext {
  final List<Vehicle> vehicles;

  /// Admin-approved driver. Unverified drivers get no recommendations.
  final bool verified;

  /// Where the driver will be (drop of the active trip) or last was (drop of
  /// the latest delivered trip). Free text, matched against the city table.
  final String? anchorPlace;

  /// True when [anchorPlace] is the drop of a trip still in progress, so a
  /// load starting nearby is a return load.
  final bool anchorIsActiveTrip;
  final List<FavouriteRoute> favourites;
  final DateTime now;

  /// Admin risk tier (`normal`, `review`, `restricted`, `suspended`).
  /// Restricted and suspended drivers get no matches.
  final String riskTier;

  /// The driver's last saved position. When there is no active trip it is
  /// the starting point for "near pickup", instead of [anchorPlace].
  final LatLng? origin;

  /// The route the driver plans to drive (`users.plannedRoute`, L5). Loads
  /// that start near its start and end near its end rank higher.
  final PlannedRoute? plannedRoute;

  const DriverContext({
    required this.vehicles,
    this.verified = true,
    this.anchorPlace,
    this.anchorIsActiveTrip = false,
    this.favourites = const [],
    required this.now,
    this.riskTier = 'normal',
    this.origin,
    this.plannedRoute,
  });
}

class LoadMatch {
  final Load load;
  final Vehicle vehicle;
  final int score;
  final List<MatchReason> reasons;

  const LoadMatch({required this.load, required this.vehicle, required this.score, required this.reasons});
}

/// Pure, offline ranking of open loads for a driver. LATER(paid): real road
/// distance / live GPS instead of the city table.
class LoadRanker {
  LoadRanker._();

  /// Loads closer than this to the trip's drop count as return loads.
  static const returnRadiusKm = 200;

  /// Vehicle can legally and physically take [load]: right type, enough
  /// capacity, free, active and no expired papers.
  /// [allowOnTrip] lets a vehicle that is finishing a trip match, so the
  /// driver can line up a return load.
  static bool vehicleFits(Vehicle v,
          {required String vehicleType, required num weight, required DateTime now, bool allowOnTrip = false}) =>
      (v.canTakeBooking || (allowOnTrip && v.isActive && v.availability == VehicleAvailability.onTrip)) &&
      v.type == vehicleType &&
      v.capacity >= weight &&
      v.expiredDocs(now).isEmpty;

  /// Number of vehicles that could carry a load of [vehicleType] / [weight].
  static int countMatchingVehicles(Iterable<Vehicle> vehicles,
          {required String vehicleType, required num weight, required DateTime now}) =>
      vehicles.where((v) => vehicleFits(v, vehicleType: vehicleType, weight: weight, now: now)).length;

  /// Best eligible vehicle for [load] with its score, or null if none fits.
  static LoadMatch? matchFor(Load load, DriverContext ctx) {
    if (!ctx.verified || !load.isOpen || !canTransactTier(ctx.riskTier)) return null;
    LoadMatch? best;
    for (final v in ctx.vehicles) {
      if (!vehicleFits(v,
          vehicleType: load.vehicleType, weight: load.weight, now: ctx.now, allowOnTrip: ctx.anchorIsActiveTrip || _farAhead(load, ctx.now))) {
        continue;
      }
      final m = _score(load, v, ctx);
      if (best == null || m.score > best.score) best = m;
    }
    return best;
  }

  /// A load scheduled more than a day ahead can use a vehicle that is busy
  /// now (SM10): it will be free again by then.
  static bool _farAhead(Load load, DateTime now) => load.scheduledAt != null && load.scheduledAt!.isAfter(now.add(const Duration(hours: 24)));

  /// Only normal and review accounts may take loads (same as the rules).
  static bool canTransactTier(String tier) => tier == 'normal' || tier == 'review';

  /// Eligible loads, best first (ties: newest first).
  static List<LoadMatch> rank(Iterable<Load> loads, DriverContext ctx) {
    final out = [for (final l in loads) ?matchFor(l, ctx)];
    out.sort((a, b) {
      final c = b.score.compareTo(a.score);
      if (c != 0) return c;
      final x = a.load.createdAt, y = b.load.createdAt;
      if (x == null || y == null) return 0;
      return y.compareTo(x);
    });
    return out;
  }

  static LoadMatch _score(Load load, Vehicle v, DriverContext ctx) {
    var score = 100;
    final reasons = <MatchReason>[];

    final anchor = ctx.anchorPlace == null ? null : findCity(ctx.anchorPlace!);
    final pickup = findCity(load.pickup);
    // With no trip in progress the driver's real position beats the last drop.
    final here = !ctx.anchorIsActiveTrip ? ctx.origin : null;
    if (here != null && pickup != null) {
      final km = (haversineKm(here.lat, here.lng, pickup.lat, pickup.lng) * 1.25).ceil();
      score += (40 - km ~/ 10).clamp(0, 40);
      if (km <= 50) reasons.add(MatchReason.nearPickup);
    } else if (anchor != null && pickup != null) {
      final km = roadKmBetween(anchor, pickup);
      score += (40 - km ~/ 10).clamp(0, 40);
      if (km <= 50) reasons.add(MatchReason.nearPickup);
      if (ctx.anchorIsActiveTrip && km <= returnRadiusKm) {
        score += 30;
        reasons.add(MatchReason.returnLoad);
      }
    } else {
      score += 10;
    }

    if (ctx.plannedRoute?.fits(load) == true) {
      score += 35;
      reasons.add(MatchReason.onYourRoute);
    }

    if (ctx.favourites.any((f) => f.matches(load))) {
      score += 25;
      reasons.add(MatchReason.favouriteRoute);
    }

    // Filling the vehicle (60%+) earns more per trip than a near-empty run.
    if (v.capacity > 0 && load.weight / v.capacity >= 0.6) {
      score += 10;
      reasons.add(MatchReason.bestFit);
    }
    if (load.budget != null) score += 5;
    return LoadMatch(load: load, vehicle: v, score: score, reasons: reasons);
  }

  /// Open loads created after [since] (the "new loads" badge). With
  /// [favourites], only loads on those routes count ("new loads on your routes").
  static int countNew(Iterable<Load> loads, DateTime? since, {List<FavouriteRoute> favourites = const []}) {
    if (since == null) return 0;
    return loads
        .where((l) =>
            l.createdAt != null &&
            l.createdAt!.toDate().isAfter(since) &&
            (favourites.isEmpty || favourites.any((f) => f.matches(l))))
        .length;
  }
}
