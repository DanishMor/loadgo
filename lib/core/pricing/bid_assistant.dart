import 'offer_bounds.dart';

/// A reason shown under the suggested range, as a translation key and values.
class BidReason {
  final String key;
  final Map<String, Object> args;
  const BidReason(this.key, [this.args = const {}]);
}

/// Suggested range for a driver's bid (MASTER-6 Task 24): around the fare
/// estimate, never below the running cost of the trip, and always inside the
/// 30%-300% of the estimate that the rules allow. Paise throughout.
class BidSuggestion {
  final int low;
  final int fair;
  final int high;
  final List<BidReason> reasons;
  const BidSuggestion({required this.low, required this.fair, required this.high, required this.reasons});
}

class BidAssistant {
  BidAssistant._();

  /// Prices are rounded to this many paise (whole ten rupees).
  static const step = 1000;

  /// The low end covers toll and fuel plus this share on top.
  static const costCoverPercent = 120;

  static int _round(int paise) => ((paise + step ~/ 2) ~/ step) * step;

  /// Null without a usable estimate: nothing sensible can be suggested.
  /// [runningCost] is toll + fuel when known (0 otherwise); [budgetPaise] is the customer's budget.
  static BidSuggestion? suggest({required int? estimateTotal, int runningCost = 0, int? budgetPaise}) {
    final e = estimateTotal;
    if (e == null || e <= 0) return null;
    final min = OfferBounds.minPaise(e), max = OfferBounds.maxPaise(e);
    int clamp(int v) => v < min ? min : (v > max ? max : v);
    final fair = clamp(_round(e));
    var low = _round(e * 90 ~/ 100);
    var raisedByCost = false;
    final cover = runningCost * costCoverPercent ~/ 100;
    if (cover > low) {
      low = _round(cover);
      raisedByCost = true;
    }
    low = clamp(low);
    if (low > fair) low = fair;
    var high = clamp(_round(e * 115 ~/ 100));
    if (high < fair) high = fair;
    final reasons = <BidReason>[
      BidReason('bidWhyEstimate', {'p': e}),
      if (runningCost > 0) BidReason(raisedByCost ? 'bidWhyCostRaised' : 'bidWhyCost', {'p': runningCost}),
      if (budgetPaise != null && budgetPaise > 0) BidReason(budgetPaise >= e ? 'bidWhyBudgetOk' : 'bidWhyBudgetLow', {'p': budgetPaise}),
      BidReason('bidWhyRule', {'min': min, 'max': max}),
    ];
    return BidSuggestion(low: low, fair: fair, high: high, reasons: reasons);
  }
}
