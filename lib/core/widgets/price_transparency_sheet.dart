import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../pricing/fare_calculator.dart';
import '../pricing/price_transparency.dart';
import '../pricing/route_rates.dart';
import '../theme/design_tokens.dart';
import 'common.dart' show formatPaise;
import 'ds/status_badge.dart';
import 'fare_breakdown.dart';

/// E27 (flag priceCard): the full price before booking: every line with "why", the platform fee and GST shown as
/// their own lines, the promise that nothing is added later, and where the customer's price sits against what was
/// paid lately on the route (when enough trips are known).
Future<void> showPriceTransparency(BuildContext context, FareBreakdown fare, {RateRange? range, int? yourPricePaise, int? tollPaise}) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => PriceTransparencySheet(fare: fare, range: range, yourPricePaise: yourPricePaise, tollPaise: tollPaise),
    );

class PriceTransparencySheet extends StatelessWidget {
  final FareBreakdown fare;
  final RateRange? range;
  final int? yourPricePaise;

  /// E33 (flag tollEstimate): expected tolls, shown apart from the price (never added to it).
  final int? tollPaise;
  const PriceTransparencySheet({super.key, required this.fare, this.range, this.yourPricePaise, this.tollPaise});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final price = yourPricePaise ?? fare.total;
    final pos = fairPosition(price, range);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(DsSpace.gutter, 0, DsSpace.gutter, DsSpace.gutter),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(header: true, child: Text(tr(context, 'pxTitle'), style: DsType.title.copyWith(color: c.textStrong))),
          const SizedBox(height: DsSpace.s3),
          FareBreakdownView(fare: fare, explain: true),
          const SizedBox(height: DsSpace.s3),
          Container(
            key: const ValueKey('ptPromise'),
            padding: const EdgeInsets.all(DsSpace.s3),
            decoration: BoxDecoration(color: c.successBg, borderRadius: DsRadius.all(DsRadius.lg)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.verified_rounded, color: c.success),
              const SizedBox(width: DsSpace.s2),
              Expanded(child: Text(tr(context, 'pxNoHidden'), style: DsType.bodySmall.copyWith(color: c.text))),
            ]),
          ),
          if (tollPaise != null && tollPaise! > 0) ...[
            const SizedBox(height: DsSpace.s3),
            Text(trf(context, 'pxToll', {'amount': formatPaise(tollPaise!)}), key: const ValueKey('pxToll'), style: DsType.bodySmall.copyWith(color: c.text)),
          ],
          if (yourPricePaise != null && yourPricePaise != fare.total) ...[
            const SizedBox(height: DsSpace.s3),
            Text(trf(context, 'pxYourPrice', {'amount': formatPaise(yourPricePaise!)}), key: const ValueKey('pxYourPrice'), style: DsType.body.copyWith(color: c.textStrong)),
          ],
          if (pos != FairPosition.unknown) ...[
            const SizedBox(height: DsSpace.s3),
            Wrap(spacing: DsSpace.s2, runSpacing: DsSpace.s1, crossAxisAlignment: WrapCrossAlignment.center, children: [
              StatusBadge(
                key: ValueKey('pxPos_${pos.name}'),
                label: tr(context, 'pxPos_${pos.name}'),
                tone: switch (pos) { FairPosition.usual => StatusTone.success, FairPosition.above => StatusTone.attention, _ => StatusTone.neutral },
              ),
              Text(trf(context, 'pxRange', {'low': formatPaise(range!.low), 'high': formatPaise(range!.high), 'n': range!.trips}), style: DsType.bodySmall.copyWith(color: c.textMuted)),
            ]),
          ],
          const SizedBox(height: DsSpace.s3),
          Text(tr(context, 'estimateNote'), style: DsType.caption.copyWith(color: c.textMuted)),
        ]),
      ),
    );
  }
}
