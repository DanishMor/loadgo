import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/design_tokens.dart';
import '../common.dart';
import 'app_button.dart';
import 'driver_mini_card.dart';
import 'status_badge.dart';

/// The tags a bid can earn. They are computed from the bids on the load, never typed by a driver.
enum BidTag { bestPrice, nearest, topRated, fastest }

String bidTagKey(BidTag t) => switch (t) {
      BidTag.bestPrice => 'uxTagBestPrice',
      BidTag.nearest => 'uxTagNearest',
      BidTag.topRated => 'uxTagTopRated',
      BidTag.fastest => 'uxTagFastest',
    };

/// One bid on a load: who, how much, how soon, with the tags it earned and the two things
/// the customer can do: accept it or answer with a price. Amounts are integer paise.
class BidCard extends StatelessWidget {
  final String driverName;
  final double? rating;
  final int trips;
  final bool verified;
  final int pricePaise;
  final int? etaMinutes;
  final List<BidTag> tags;
  final String? note;
  final Widget? trust;
  final VoidCallback? onAccept;
  final VoidCallback? onCounter;

  /// The customer already answered this bid with a price; shown instead of the counter button.
  final int? counterPaise;

  /// E17: a drawing of the offered vehicle, shown under the driver when the vehicle catalog is on.
  final Widget? vehicle;

  const BidCard({
    super.key,
    required this.driverName,
    required this.pricePaise,
    this.rating,
    this.trips = 0,
    this.verified = false,
    this.etaMinutes,
    this.tags = const [],
    this.note,
    this.trust,
    this.onAccept,
    this.onCounter,
    this.counterPaise,
    this.vehicle,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Container(
      padding: const EdgeInsets.all(DsSpace.s4),
      decoration: BoxDecoration(color: c.surface, borderRadius: DsRadius.all(DsRadius.lg), border: Border.all(color: c.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        DriverMiniCard(name: driverName, rating: rating, trips: trips, verified: verified, trust: trust),
        if (vehicle != null) ...[const SizedBox(height: DsSpace.s2), Align(alignment: AlignmentDirectional.centerStart, child: vehicle!)],
        const SizedBox(height: DsSpace.s3),
        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.end, spacing: DsSpace.s3, children: [
          Directionality(textDirection: TextDirection.ltr, child: Text(formatPaise(pricePaise), key: const ValueKey('bidPrice'), style: DsType.headline.copyWith(color: c.textStrong))),
          if (etaMinutes != null) Text(trf(context, 'uxEtaMin', {'n': etaMinutes!}), key: const ValueKey('bidEta'), style: DsType.bodySmall.copyWith(color: c.textMuted)),
        ]),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: DsSpace.s2),
          Wrap(spacing: DsSpace.s2, runSpacing: DsSpace.s1, children: [for (final t in tags) StatusBadge(label: tr(context, bidTagKey(t)), tone: StatusTone.progress)]),
        ],
        if (note != null && note!.isNotEmpty) ...[
          const SizedBox(height: DsSpace.s2),
          Text(note!, style: DsType.bodySmall.copyWith(color: c.text)),
        ],
        const SizedBox(height: DsSpace.s3),
        // Stacked, not side by side: two big buttons do not fit in a row at large text.
        AppButton(key: const ValueKey('bidAccept'), label: tr(context, 'uxAccept'), onPressed: onAccept),
        if (onCounter != null && counterPaise == null) ...[
          const SizedBox(height: DsSpace.s2),
          AppButton(key: const ValueKey('bidCounter'), label: tr(context, 'uxCounter'), kind: AppButtonKind.secondary, onPressed: onCounter),
        ],
        if (counterPaise != null) ...[
          const SizedBox(height: DsSpace.s2),
          Directionality(textDirection: TextDirection.ltr, child: Text(formatPaise(counterPaise!), key: const ValueKey('bidCounterShown'), textAlign: TextAlign.center, style: DsType.subtitle.copyWith(color: c.textMuted))),
        ],
      ]),
    );
  }
}
