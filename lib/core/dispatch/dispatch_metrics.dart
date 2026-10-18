import '../constants/logistics.dart';
import '../models/load.dart';
import '../models/offer.dart';
import 'dispatch_config_service.dart';
import 'dispatch_models.dart';
import 'instant_progress.dart';
import '../pricing/cities.dart';

/// One load in the admin dispatch monitor (U17).
class DispatchRow {
  final Load load;
  final int bids;

  /// The wave open now for a live instant load (1-based), or null.
  final int? wave;
  final bool stalled;

  /// Seconds from posting to the first bid, and to a driver taking it.
  final int? firstBidSeconds;
  final int? fillSeconds;

  const DispatchRow({required this.load, required this.bids, this.wave, this.stalled = false, this.firstBidSeconds, this.fillSeconds});
}

/// The numbers at the top of the monitor.
class DispatchSummary {
  final int live;
  final int filled;
  final int expiredNoBid;
  final int expiredWithBids;
  final int? medianFirstBidSeconds;
  final int? medianFillSeconds;

  /// Filled / (filled + expired), in whole percent, or null while there is nothing to judge.
  final int? acceptancePercent;

  /// Average of (final price / fare estimate) in whole percent over filled loads that had an estimate.
  final int? priceVsEstimatePercent;
  final int noShowCancels;

  const DispatchSummary({
    required this.live,
    required this.filled,
    required this.expiredNoBid,
    required this.expiredWithBids,
    this.medianFirstBidSeconds,
    this.medianFillSeconds,
    this.acceptancePercent,
    this.priceVsEstimatePercent,
    this.noShowCancels = 0,
  });
}

class DispatchSnapshot {
  final List<DispatchRow> rows;
  final DispatchSummary summary;
  const DispatchSnapshot(this.rows, this.summary);
}

/// Works the monitor out of the recent loads, the bids and the no-show count. Pure.
class DispatchMetrics {
  DispatchMetrics._();

  static int? median(List<int> v) {
    if (v.isEmpty) return null;
    final s = [...v]..sort();
    final mid = s.length ~/ 2;
    return s.length.isOdd ? s[mid] : ((s[mid - 1] + s[mid]) / 2).round();
  }

  static DispatchSnapshot compute({
    required List<Load> loads,
    required List<Offer> offers,
    required DateTime now,
    int noShowCancels = 0,
    DispatchConfig? config,
  }) {
    final byLoad = <String, List<Offer>>{};
    for (final o in offers) {
      byLoad.putIfAbsent(o.loadId, () => []).add(o);
    }
    final rows = <DispatchRow>[];
    final firstBids = <int>[], fills = <int>[], ratios = <int>[];
    var live = 0, filled = 0, expiredNoBid = 0, expiredWithBids = 0;
    final cfg = config ?? DispatchConfigService.current;
    for (final l in loads) {
      final os = byLoad[l.id] ?? const <Offer>[];
      final created = l.createdAt?.toDate();
      int? firstBid;
      if (created != null) {
        final times = [for (final o in os) if (o.createdAt != null) o.createdAt!.toDate().difference(created).inSeconds];
        if (times.isNotEmpty) {
          firstBid = times.reduce((a, b) => a < b ? a : b).clamp(0, 1 << 30);
          firstBids.add(firstBid);
        }
      }
      int? fill;
      final isFilled = l.bookingId != null && (l.status == LoadStatus.matched || l.status == LoadStatus.closed);
      if (isFilled) {
        filled++;
        if (created != null && l.matchedAt != null) {
          fill = l.matchedAt!.toDate().difference(created).inSeconds.clamp(0, 1 << 30);
          fills.add(fill);
        }
        final est = l.estimate?.total;
        final confirmed = os.where((o) => o.status == OfferStatus.confirmed).toList();
        final paise = confirmed.isNotEmpty ? confirmed.first.pricePaise : (l.budget == null ? null : (l.budget! * 100).round());
        if (est != null && est > 0 && paise != null && paise > 0) ratios.add((paise * 100 / est).round());
      } else if (l.status == LoadStatus.closed && !l.cancelled) {
        if (os.isEmpty) {
          expiredNoBid++;
        } else {
          expiredWithBids++;
        }
      }
      int? wave;
      var stalled = false;
      if (l.isOpen) {
        live++;
        if (l.mode == LoadMode.instant && created != null) {
          final p = InstantProgress.at(cfg.forCity(findCity(l.pickup)?.name), createdAt: created, now: now, boost: l.ringBoost);
          wave = p.wave + 1;
          stalled = p.stalled;
        }
      }
      rows.add(DispatchRow(load: l, bids: os.length, wave: wave, stalled: stalled, firstBidSeconds: firstBid, fillSeconds: fill));
    }
    final judged = filled + expiredNoBid + expiredWithBids;
    return DispatchSnapshot(
      rows,
      DispatchSummary(
        live: live,
        filled: filled,
        expiredNoBid: expiredNoBid,
        expiredWithBids: expiredWithBids,
        medianFirstBidSeconds: median(firstBids),
        medianFillSeconds: median(fills),
        acceptancePercent: judged == 0 ? null : (filled * 100 / judged).round(),
        priceVsEstimatePercent: ratios.isEmpty ? null : (ratios.reduce((a, b) => a + b) / ratios.length).round(),
        noShowCancels: noShowCancels,
      ),
    );
  }
}
