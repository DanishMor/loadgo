import 'dart:async';

import '../features/features.dart';
import '../models/load.dart';
import '../models/offer.dart';
import '../services/backend.dart';
import '../services/features_service.dart';
import '../services/load_service.dart';
import '../services/offer_service.dart';
import '../trust/public_trust.dart';
import 'bid_ranking.dart';
import 'trust_lookup.dart';

/// U14: the customer's auto-accept rule, applied while the customer's app is open. When a bid on one of the
/// customer's open loads fits the rule (price up to the limit, rating at least the minimum, verified when asked),
/// the cheapest such bid is accepted: it is selected and the others are closed, exactly as a tap on Accept does.
///
/// LIMIT (docs/FLOW_SPEC.md): nothing is accepted while the app is closed. The server function `autoAcceptBids`
/// (switch `dispatchV2`, not deployed yet) applies the same rule with the app closed.
class AutoAcceptWatcher {
  AutoAcceptWatcher._();

  static StreamSubscription<List<Load>>? _loadSub;
  static StreamSubscription<List<Offer>>? _offerSub;
  static List<Load> _loads = const [];
  static List<Offer> _offers = const [];
  static bool _busy = false, _dirty = false;
  static final Set<String> _tried = {};
  static final Map<String, PublicTrust?> _trust = {};

  /// Tests replace how a driver's trust summary is read.
  static Future<PublicTrust?> Function(String uid) trustReader = TrustLookup.of;

  /// Starts listening (only while `dispatchV2` is on and someone is signed in). Safe to call twice.
  static void start() {
    if (_loadSub != null || Backend.uid == null || !FeaturesService.isOn(FeatureKey.dispatchV2)) return;
    _loadSub = LoadService.watchMine().listen((l) {
      _loads = l;
      _kick();
    }, onError: (_) {});
    _offerSub = OfferService.watchForCustomer().listen((o) {
      _offers = o;
      _kick();
    }, onError: (_) {});
  }

  /// Stops listening and forgets what it knows (sign out).
  static void stop() {
    _loadSub?.cancel();
    _offerSub?.cancel();
    _loadSub = _offerSub = null;
    _loads = const [];
    _offers = const [];
    _tried.clear();
    _trust.clear();
  }

  static void _kick() {
    if (_busy) {
      _dirty = true;
      return;
    }
    _busy = true;
    () async {
      try {
        do {
          _dirty = false;
          await evaluate(_loads, _offers);
        } while (_dirty);
      } finally {
        _busy = false;
      }
    }();
  }

  /// One pass over [loads] and [offers]: accepts at most one bid per load. Returns the offer ids accepted.
  static Future<List<String>> evaluate(List<Load> loads, List<Offer> offers) async {
    final accepted = <String>[];
    for (final load in loads) {
      final rule = load.autoAccept;
      if (rule == null || !load.isOpen || load.shipperId != Backend.uid) continue;
      final mine = [for (final o in offers) if (o.loadId == load.id) o];
      final pending = [for (final o in mine) if (o.status == OfferStatus.pending && !_tried.contains(o.id)) o];
      if (pending.isEmpty || mine.any((o) => o.status == OfferStatus.selected)) continue; // someone is already chosen
      final views = <BidView>[];
      for (final o in pending) {
        PublicTrust? t;
        if (rule.minRating > 0) {
          t = _trust.containsKey(o.driverId) ? _trust[o.driverId] : (_trust[o.driverId] = await trustReader(o.driverId));
        }
        views.add(BidView(o, rating: t?.rating, verified: t?.verified ?? false));
      }
      final pick = BidRanking.autoAcceptPick(views, rule);
      if (pick == null) continue;
      _tried.add(pick.offer.id);
      try {
        await OfferService.acceptBid(pick.offer, mine);
        accepted.add(pick.offer.id);
      } catch (_) {
        // The bid changed under us (withdrawn, accepted by hand): the next pass looks again.
      }
    }
    return accepted;
  }

  /// For tests: forget the tried set.
  static void resetForTest() {
    stop();
    trustReader = TrustLookup.of;
  }
}
