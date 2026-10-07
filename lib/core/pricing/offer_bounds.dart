/// Sanity limits for a driver's price against the fare estimate of the load:
/// from 30% to 300% of it. Integer paise only. Rules use the same integer
/// formula (`price * 100 >= estimate * 30` and `<= estimate * 300`).
/// Loads without an estimate (older ones, unknown distance) have no limits.
class OfferBounds {
  OfferBounds._();

  static const minPercent = 30;
  static const maxPercent = 300;

  /// Lowest allowed price (rounded up to a whole paisa).
  static int minPaise(int estimateTotal) => (estimateTotal * minPercent + 99) ~/ 100;

  static int maxPaise(int estimateTotal) => estimateTotal * maxPercent ~/ 100;

  /// null when fine, 'low' or 'high' when outside the range.
  static String? check(int pricePaise, int? estimateTotal) {
    if (estimateTotal == null || estimateTotal <= 0) return null;
    if (pricePaise * 100 < estimateTotal * minPercent) return 'low';
    if (pricePaise * 100 > estimateTotal * maxPercent) return 'high';
    return null;
  }
}
