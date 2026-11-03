import 'bid_ranking.dart';

/// E38 (flag bidExplain): why a bid wears its highlight, in facts the customer can check. Each line is a words key
/// with its numbers; nothing is said when a fact is not known.
class BidWhy {
  final String key;
  final Map<String, Object> args;
  const BidWhy(this.key, [this.args = const {}]);
}

class BidExplain {
  BidExplain._();

  /// The reasons for [bid] among the live [bids], one per highlight it has.
  static List<BidWhy> forBid(BidView bid, Iterable<BidView> bids, Set<BidTagKind> tags) {
    final others = [for (final b in bids) if (b.offer.id != bid.offer.id) b];
    final out = <BidWhy>[];
    if (tags.contains(BidTagKind.bestPrice)) {
      final next = others.map((b) => b.pricePaise).where((p) => p > bid.pricePaise).fold<int?>(null, (a, p) => a == null || p < a ? p : a);
      out.add(next == null ? BidWhy('bxBestPrice', {'n': others.length + 1}) : BidWhy('bxBestPriceBy', {'n': others.length + 1, 'diff': next - bid.pricePaise}));
    }
    if (tags.contains(BidTagKind.nearest) && bid.offer.pickupKm != null) out.add(BidWhy('bxNearest', {'km': bid.offer.pickupKm!}));
    if (tags.contains(BidTagKind.topRated) && bid.rating != null) out.add(BidWhy('bxTopRated', {'r': bid.rating!.toStringAsFixed(1)}));
    if (tags.contains(BidTagKind.fastest) && bid.offer.etaMinutes != null) out.add(BidWhy('bxFastest', {'m': bid.offer.etaMinutes!}));
    return out;
  }
}
