import '../models/load.dart';
import '../models/offer.dart';
import '../services/backend.dart';
import '../services/server_clock.dart';
import 'dispatch_metrics.dart';
import '../services/safe_docs.dart';

/// Reads what the admin dispatch monitor needs, once (U17): the newest 200 loads, the newest 400 bids and the
/// cancelled bookings. The rules let only `super` and `ops` read the bids of others.
class DispatchMonitorService {
  DispatchMonitorService._();

  /// Cancel reasons that mean "the other person did not turn up" (docs/DECISIONS.md, U15).
  static const noShowReasons = ['customer_unreachable', 'driver_delay'];

  static Future<DispatchSnapshot> load({DateTime? now}) async {
    final db = Backend.db;
    final loads = (await db.collection('loads').orderBy('createdAt', descending: true).limit(200).get()).docs.parse(Load.fromDoc);
    final offers = (await db.collection('offers').orderBy('createdAt', descending: true).limit(400).get()).docs.parse(Offer.fromDoc);
    final cancelled = await db.collection('bookings').where('status', isEqualTo: 'cancelled').limit(200).get();
    var noShows = 0;
    for (final d in cancelled.docs) {
      final c = d.data()['cancellation'];
      if (c is Map && noShowReasons.contains(c['reason'])) noShows++;
    }
    return DispatchMetrics.compute(loads: loads, offers: offers, now: now ?? ServerClock.now(), noShowCancels: noShows);
  }
}
