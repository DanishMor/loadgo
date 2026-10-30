/// E28 (flag partLoad, planned until its rules are published): a part load shares one truck with other loads on the
/// same lane. The customer books a share of the load space; the price is that share of a full-truck price plus a
/// handling margin, never more than the full truck. All numbers here are config defaults for the owner to review
/// (docs/OWNER_REVIEW.md), not market facts.
class PartLoadConfig {
  /// The smallest share sold (a pallet or two is still a stop for the truck).
  final double minShare;

  /// The largest share that is still a part load; above it the customer should book the whole truck.
  final double maxShare;

  /// Added for the extra stop, handling and the wait for other loads (0.15 = 15%).
  final double handling;

  const PartLoadConfig({this.minShare = 0.1, this.maxShare = 0.7, this.handling = 0.15});

  static const standard = PartLoadConfig();

  /// Defensive: a broken config document falls back to [standard].
  static PartLoadConfig fromMap(Map<String, dynamic>? m) {
    double? n(String k) {
      final v = m?[k];
      return v is num ? v.toDouble() : null;
    }

    final min = n('minShare'), max = n('maxShare'), h = n('handling');
    final ok = min != null && max != null && h != null && min > 0 && min < max && max < 1 && h >= 0 && h <= 0.5;
    return ok ? PartLoadConfig(minShare: min, maxShare: max, handling: h) : standard;
  }
}

/// The share of the truck's load space the goods take, from weight and (when known) volume, whichever is larger.
double spaceShare({required double weightTons, required double truckTons, double? volumeCft, double? truckCft}) {
  if (truckTons <= 0) return 1;
  var share = weightTons / truckTons;
  if (volumeCft != null && truckCft != null && truckCft > 0) {
    final byVolume = volumeCft / truckCft;
    if (byVolume > share) share = byVolume;
  }
  return share.clamp(0, 1).toDouble();
}

enum PartLoadAdvice { ok, tooSmall, bookFullTruck }

PartLoadAdvice partLoadAdvice(double share, [PartLoadConfig c = PartLoadConfig.standard]) =>
    share > c.maxShare ? PartLoadAdvice.bookFullTruck : (share < c.minShare ? PartLoadAdvice.tooSmall : PartLoadAdvice.ok);

/// The part-load price in paise: the (at least minimum) share of the full-truck price plus handling, rounded to ten
/// rupees, never above the full-truck price.
int partLoadPricePaise(int fullTruckPaise, double share, [PartLoadConfig c = PartLoadConfig.standard]) {
  if (fullTruckPaise <= 0) return 0;
  final s = share < c.minShare ? c.minShare : share;
  final raw = (fullTruckPaise * s * (1 + c.handling)).round();
  final rounded = ((raw + 500) ~/ 1000) * 1000;
  return rounded > fullTruckPaise ? fullTruckPaise : rounded;
}

/// Shares already on one truck plus a new one must fit in the load space.
bool fitsTruck(Iterable<double> booked, double next) => booked.fold<double>(0, (a, s) => a + s) + next <= 1.0 + 1e-9;
