import 'package:flutter/material.dart';

import '../core/dispatch/dispatch_metrics.dart';
import '../core/dispatch/dispatch_models.dart';
import '../core/dispatch/dispatch_monitor_service.dart';
import '../core/l10n/l10n.dart';
import '../core/theme/design_tokens.dart';
import '../core/widgets/common.dart';
import '../core/widgets/ds/app_top_bar.dart';
import '../core/widgets/ds/sheet_kit.dart';
import '../core/widgets/ds/status_badge.dart';
import '../core/widgets/live_stream.dart';
import '../core/widgets/stat_tile.dart';

/// Admin > Dispatch monitor (U17): live loads with their ring and bids, and the numbers that say whether the
/// engine works: time to first bid, time to fill, how many were taken, price against the estimate, loads that
/// ended without a bid. Read once; Refresh reloads. For `super` and `ops` (the rules allow only them to read bids).
class AdminDispatchMonitorScreen extends StatefulWidget {
  /// Tests give the data directly.
  final Future<DispatchSnapshot> Function()? load;
  const AdminDispatchMonitorScreen({super.key, this.load});

  @override
  State<AdminDispatchMonitorScreen> createState() => _AdminDispatchMonitorScreenState();
}

class _AdminDispatchMonitorScreenState extends State<AdminDispatchMonitorScreen> {
  late Future<DispatchSnapshot> _data = (widget.load ?? DispatchMonitorService.load)();

  void _refresh() {
    final next = (widget.load ?? DispatchMonitorService.load)();
    setState(() {
      _data = next;
    });
  }

  String _duration(BuildContext context, int? s) {
    if (s == null) return tr(context, 'dmNone');
    return s >= 90 ? trf(context, 'dmMinutes', {'n': (s / 60).round()}) : trf(context, 'dmSeconds', {'n': s});
  }

  String _modeLabel(BuildContext context, LoadMode m) => tr(context, switch (m) {
        LoadMode.instant => 'dmModeInstant',
        LoadMode.bid => 'dmModeBid',
        LoadMode.scheduled => 'dmModeScheduled',
      });

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Scaffold(
      appBar: AppTopBar(title: tr(context, 'adminDispatchMonitor'), actions: [IconButton(key: const ValueKey('dmRefresh'), tooltip: tr(context, 'uxTryAgain'), icon: const Icon(Icons.refresh_rounded), onPressed: _refresh)]),
      body: FutureBuilder<DispatchSnapshot>(
        future: _data,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(DsSpace.gutter), child: SkeletonList());
          if (snap.hasError) return ErrorState(error: snap.error, onRetry: _refresh);
          final s = snap.data!.summary;
          final rows = snap.data!.rows;
          String pct(int? v) => v == null ? tr(context, 'dmNone') : '$v%';
          return ListView(padding: const EdgeInsets.all(DsSpace.gutter), children: [
            StatTile(label: tr(context, 'dmLive'), value: '${s.live}', icon: Icons.radar_rounded),
            const SizedBox(height: DsSpace.s2),
            StatTile(label: tr(context, 'dmFilled'), value: '${s.filled}', icon: Icons.check_circle_outline_rounded),
            const SizedBox(height: DsSpace.s2),
            StatTile(label: tr(context, 'dmExpiredNoBid'), value: '${s.expiredNoBid}', icon: Icons.hourglass_disabled_rounded),
            const SizedBox(height: DsSpace.s2),
            StatTile(label: tr(context, 'dmExpiredBids'), value: '${s.expiredWithBids}', icon: Icons.gavel_rounded),
            const SizedBox(height: DsSpace.s2),
            StatTile(label: tr(context, 'dmFirstBid'), value: _duration(context, s.medianFirstBidSeconds), icon: Icons.timer_outlined),
            const SizedBox(height: DsSpace.s2),
            StatTile(label: tr(context, 'dmFillTime'), value: _duration(context, s.medianFillSeconds), icon: Icons.timelapse_rounded),
            const SizedBox(height: DsSpace.s2),
            StatTile(label: tr(context, 'dmAcceptance'), value: pct(s.acceptancePercent), icon: Icons.percent_rounded),
            const SizedBox(height: DsSpace.s2),
            StatTile(label: tr(context, 'dmPriceVsEstimate'), value: pct(s.priceVsEstimatePercent), icon: Icons.compare_arrows_rounded),
            const SizedBox(height: DsSpace.s2),
            StatTile(label: tr(context, 'dmNoShows'), value: '${s.noShowCancels}', icon: Icons.person_off_outlined),
            const SizedBox(height: DsSpace.s2),
            StatTile(label: tr(context, 'dmShown'), value: tr(context, 'dmNone'), icon: Icons.visibility_outlined),
            Padding(padding: const EdgeInsets.only(top: DsSpace.s1, bottom: DsSpace.s4), child: Text(tr(context, 'dmShownNote'), style: DsType.caption.copyWith(color: c.textMuted))),
            Semantics(header: true, child: Text(tr(context, 'dmRecent'), style: DsType.title.copyWith(color: c.textStrong))),
            const SizedBox(height: DsSpace.s2),
            for (final r in rows.take(60))
              Padding(
                key: ValueKey('dmRow_${r.load.id}'),
                padding: const EdgeInsets.only(bottom: DsSpace.s2),
                child: AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${r.load.pickup} → ${r.load.drop}', maxLines: 2, overflow: TextOverflow.ellipsis, style: DsType.subtitle.copyWith(color: c.textStrong)),
                    const SizedBox(height: DsSpace.s1),
                    Wrap(spacing: DsSpace.s2, runSpacing: DsSpace.s1, children: [
                      StatusBadge(label: _modeLabel(context, r.load.mode), tone: StatusTone.neutral),
                      StatusBadge(label: trf(context, 'dmBids', {'n': r.bids}), tone: r.bids > 0 ? StatusTone.progress : StatusTone.neutral),
                      if (r.wave != null) StatusBadge(label: r.stalled ? tr(context, 'dmStalled') : trf(context, 'dmRing', {'n': r.wave!}), tone: r.stalled ? StatusTone.attention : StatusTone.progress),
                    ]),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
