import '../models/offer.dart';
import 'dispatch_models.dart';

/// The tags a bid can earn (U13). They are worked out from the bids on the load, never typed by a driver.
enum BidTagKind { bestPrice, nearest, topRated, fastest }

/// What the customer sorts by. The chips in the Bid Room.
enum BidSort { bestPrice, nearest, topRated, fastest }

/// One bid with what is known about its driver. [rating] comes from `public_trust` (server written) when the
/// `tripTrustCard` data exists; null when unknown.
class BidView {
  final Offer offer;
  final double? rating;
  final bool verified;
  const BidView(this.offer, {this.rating, this.verified = false});

  int get pricePaise => offer.pricePaise;
  BidFacts get facts => BidFacts(pricePaise: offer.pricePaise, rating: rating, verified: verified || offer.companyVerified);
}

/// Sorting, tags and "which bid may the auto-accept rule take" for the bids of one load.
class BidRanking {
  BidRanking._();

  /// Only bids that can still be acted on: pending, or countered and waiting for the driver.
  static List<BidView> live(Iterable<BidView> bids) => [for (final b in bids) if (b.offer.status == OfferStatus.pending) b];

  static int _cmpNullLast<T extends num>(T? a, T? b, {bool higherFirst = false}) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return higherFirst ? b.compareTo(a) : a.compareTo(b);
  }

  /// The bids in the order the chip asks for. Ties fall back to the lower price, then the earlier bid, so the
  /// order is stable and never jumps.
  static List<BidView> sort(Iterable<BidView> bids, BidSort by) {
    final list = [...bids];
    int tie(BidView a, BidView b) {
      final p = a.pricePaise.compareTo(b.pricePaise);
      if (p != 0) return p;
      final ta = a.offer.createdAt?.millisecondsSinceEpoch, tb = b.offer.createdAt?.millisecondsSinceEpoch;
      final t = _cmpNullLast(ta, tb);
      return t != 0 ? t : a.offer.id.compareTo(b.offer.id);
    }

    list.sort((a, b) {
      final c = switch (by) {
        BidSort.bestPrice => a.pricePaise.compareTo(b.pricePaise),
        BidSort.nearest => _cmpNullLast(a.offer.pickupKm, b.offer.pickupKm),
        BidSort.topRated => _cmpNullLast(a.rating, b.rating, higherFirst: true),
        BidSort.fastest => _cmpNullLast(a.offer.etaMinutes, b.offer.etaMinutes),
      };
      return c != 0 ? c : tie(a, b);
    });
    return list;
  }

  /// The tags of every bid: the lowest price, the smallest distance, the best rating and the shortest ETA.
  /// A tag needs at least two bids to mean something, and a tie gives the tag to every tied bid.
  static Map<String, Set<BidTagKind>> tags(Iterable<BidView> bids) {
    final list = [...bids];
    final out = <String, Set<BidTagKind>>{for (final b in list) b.offer.id: <BidTagKind>{}};
    if (list.length < 2) return out;
    void award<T extends num>(BidTagKind kind, T? Function(BidView) value, {bool higherBetter = false}) {
      final known = [for (final b in list) if (value(b) != null) b];
      if (known.length < 2) return;
      final best = known.map((b) => value(b)!).reduce((a, b) => higherBetter ? (a >= b ? a : b) : (a <= b ? a : b));
      final all = known.map((b) => value(b)!).toSet();
      if (all.length == 1) return; // everyone equal: nobody stands out
      for (final b in known) {
        if (value(b) == best) out[b.offer.id]!.add(kind);
      }
    }

    award<int>(BidTagKind.bestPrice, (b) => b.pricePaise);
    award<int>(BidTagKind.nearest, (b) => b.offer.pickupKm);
    award<double>(BidTagKind.topRated, (b) => b.rating, higherBetter: true);
    award<int>(BidTagKind.fastest, (b) => b.offer.etaMinutes);
    return out;
  }

  /// The first bid (best price, then earliest) that the customer's auto-accept rule allows, or null.
  static BidView? autoAcceptPick(Iterable<BidView> bids, AutoAccept? rule) {
    if (rule == null) return null;
    for (final b in sort(live(bids), BidSort.bestPrice)) {
      if (rule.accepts(b.facts)) return b;
    }
    return null;
  }
}

/// What to tell the customer when the bid window is over (or nearly) and nobody has bid (U13).
enum NoBidSuggestion { raisePrice, moreTime, goInstant, schedule }

class BidSuggestions {
  BidSuggestions._();

  /// Empty while bids exist or the window is still open. Otherwise the four clear next steps, the most useful first.
  static List<NoBidSuggestion> whenNoBids({required int liveBids, required DateTime? windowEnds, required DateTime now}) {
    if (liveBids > 0) return const [];
    if (windowEnds != null && windowEnds.isAfter(now)) return const [];
    return const [NoBidSuggestion.raisePrice, NoBidSuggestion.moreTime, NoBidSuggestion.goInstant, NoBidSuggestion.schedule];
  }
}
