import 'dart:async';

import 'package:flutter/material.dart';

import '../core/dispatch/instant_progress.dart';
import '../core/dispatch/load_dispatch_service.dart';
import '../core/errors/error_text.dart';
import '../core/l10n/l10n.dart';
import '../core/models/load.dart';
import '../core/services/server_clock.dart';
import '../core/theme/design_tokens.dart';
import '../core/widgets/common.dart';
import '../core/widgets/ds/app_button.dart';
import '../core/widgets/ds/countdown_ring.dart';

/// U12: the customer's view of an instant load while drivers are being asked: the ring runs until the next wave,
/// the reach says how far the search goes, and when the last wave ran out with nobody saying yes the card offers
/// "raise the price 5% or 10%" and "search wider". Each button is one update of the load that the rules check.
class InstantWaitCard extends StatefulWidget {
  final Load load;

  /// Tests replace the clock.
  final DateTime Function()? now;

  const InstantWaitCard({super.key, required this.load, this.now});

  @override
  State<InstantWaitCard> createState() => _InstantWaitCardState();
}

class _InstantWaitCardState extends State<InstantWaitCard> {
  Timer? _t;
  bool _busy = false;

  DateTime _now() => (widget.now ?? ServerClock.now)();

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      if (mounted) showSnack(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _raise(int percent) => _run(() async {
        final next = await LoadDispatchService.raisePrice(widget.load, percent);
        if (!mounted) return;
        showSnack(context, next == null ? tr(context, 'uxPriceLimit') : trf(context, 'uxPriceRaised', {'amount': formatPaise(next * 100)}));
      });

  Future<void> _widen() => _run(() async {
        await LoadDispatchService.widenRange(widget.load);
      });

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final load = widget.load;
    final created = load.createdAt?.toDate();
    final p = created == null ? null : InstantProgress.at(LoadDispatchService.configFor(load), createdAt: created, now: _now(), boost: load.ringBoost);
    final canWiden = load.ringBoost < LoadDispatchService.maxBoost;
    return Container(
      padding: const EdgeInsets.all(DsSpace.s4),
      decoration: BoxDecoration(color: c.surface, borderRadius: DsRadius.all(DsRadius.lg), border: Border.all(color: c.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Semantics(header: true, child: Text(tr(context, p?.stalled == true ? 'uxInstStalled' : 'uxInstTitle'), style: DsType.title.copyWith(color: c.textStrong))),
        const SizedBox(height: DsSpace.s3),
        if (p != null && !p.stalled)
          Row(children: [
            CountdownRing(
              key: ValueKey('instRing${p.wave}'),
              endsAt: _now().add(Duration(seconds: p.secondsLeft)),
              totalSeconds: p.stageSeconds,
              now: _now,
            ),
            const SizedBox(width: DsSpace.s4),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(trf(context, 'uxInstReach', {'km': p.reachKm}), key: const ValueKey('instReach'), style: DsType.subtitle.copyWith(color: c.text)),
                Text(trf(context, 'uxInstRound', {'n': p.wave + 1, 'm': p.waves}), style: DsType.bodySmall.copyWith(color: c.textMuted)),
              ]),
            ),
          ]),
        if (p == null) const LinearProgressIndicator(),
        if (load.budget != null) ...[
          const SizedBox(height: DsSpace.s3),
          Text(trf(context, 'uxPriceNow', {'amount': formatPaise((load.budget! * 100).round())}), key: const ValueKey('instPrice'), style: DsType.body.copyWith(color: c.text)),
        ],
        if (p?.stalled == true) ...[
          const SizedBox(height: DsSpace.s2),
          Text(tr(context, 'uxInstStalledHint'), style: DsType.bodySmall.copyWith(color: c.textMuted)),
          const SizedBox(height: DsSpace.s3),
          AppButton(key: const ValueKey('instRaise5'), label: tr(context, 'uxRaise5'), icon: Icons.trending_up_rounded, loading: _busy, onPressed: () => _raise(5)),
          const SizedBox(height: DsSpace.s2),
          AppButton(key: const ValueKey('instRaise10'), label: tr(context, 'uxRaise10'), kind: AppButtonKind.secondary, icon: Icons.trending_up_rounded, onPressed: _busy ? null : () => _raise(10)),
          const SizedBox(height: DsSpace.s2),
          if (canWiden)
            AppButton(key: const ValueKey('instWiden'), label: tr(context, 'uxWiden'), kind: AppButtonKind.tertiary, icon: Icons.zoom_out_map_rounded, onPressed: _busy ? null : _widen)
          else
            Text(tr(context, 'uxWidenMax'), textAlign: TextAlign.center, style: DsType.bodySmall.copyWith(color: c.textMuted)),
        ],
      ]),
    );
  }
}
