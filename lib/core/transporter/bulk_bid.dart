import '../models/load.dart';
import '../models/vehicle.dart';
import '../pricing/offer_bounds.dart';

/// Why a load in a bulk bid is left out.
enum BulkSkip { noEstimate, noVehicle, lowMargin }

/// One load of a bulk bid with the vehicle and price chosen for it.
class BulkBidItem {
  final Load load;
  final Vehicle? vehicle;
  final int? pricePaise;

  /// Toll and fuel for the trip, when the distance is known.
  final int? runningCostPaise;
  final BulkSkip? skip;
  const BulkBidItem(this.load, {this.vehicle, this.pricePaise, this.runningCostPaise, this.skip});

  bool get willBid => skip == null;

  /// What is left of the price after running cost (null when the cost is unknown).
  int? get marginPaise => pricePaise == null || runningCostPaise == null ? null : pricePaise! - runningCostPaise!;
}

/// Bids on several loads at once under a margin rule (MASTER-6 Task 29): the
/// price is the fare estimate plus a markup, and a load is left out when the
/// price would not leave the minimum margin over toll and fuel.
class BulkBid {
  BulkBid._();

  static const maxLoads = 20;
  static const markupChoices = [0, 5, 10, 15, 20];
  static const marginChoices = [0, 5, 10, 15, 20, 30];

  /// Estimate plus [markupPercent], in whole ten rupees, inside the bounds the rules allow.
  static int? priceFor(int? estimateTotal, int markupPercent) {
    final e = estimateTotal;
    if (e == null || e <= 0) return null;
    final raw = e * (100 + markupPercent) ~/ 100;
    final rounded = ((raw + 500) ~/ 1000) * 1000;
    final min = OfferBounds.minPaise(e), max = OfferBounds.maxPaise(e);
    return rounded < min ? min : (rounded > max ? max : rounded);
  }

  /// The smallest free vehicle that can carry [load]; one of the load's own
  /// type is preferred over a different type of the same capacity.
  static Vehicle? vehicleFor(Load load, Iterable<Vehicle> vehicles, DateTime now) {
    Vehicle? best;
    for (final v in vehicles) {
      if (!v.canTakeBooking || v.capacity < load.weight || v.expiredDocs(now).isNotEmpty) continue;
      if (best == null) {
        best = v;
        continue;
      }
      final sameType = v.type == load.vehicleType, bestSame = best.type == load.vehicleType;
      if (sameType != bestSame) {
        if (sameType) best = v;
      } else if (v.capacity < best.capacity) {
        best = v;
      }
    }
    return best;
  }

  /// [runningCost] gives toll + fuel for a load and vehicle, or null when the distance is unknown.
  static List<BulkBidItem> plan(
    Iterable<Load> loads,
    Iterable<Vehicle> vehicles, {
    required int markupPercent,
    required int minMarginPercent,
    required int? Function(Load, Vehicle) runningCost,
    required DateTime now,
  }) {
    final out = <BulkBidItem>[];
    for (final l in loads.take(maxLoads)) {
      final price = priceFor(l.estimate?.total, markupPercent);
      if (price == null) {
        out.add(BulkBidItem(l, skip: BulkSkip.noEstimate));
        continue;
      }
      final v = vehicleFor(l, vehicles, now);
      if (v == null) {
        out.add(BulkBidItem(l, pricePaise: price, skip: BulkSkip.noVehicle));
        continue;
      }
      final cost = runningCost(l, v);
      final low = cost != null && (price - cost) * 100 < price * minMarginPercent;
      out.add(BulkBidItem(l, vehicle: v, pricePaise: price, runningCostPaise: cost, skip: low ? BulkSkip.lowMargin : null));
    }
    return out;
  }
}
