import 'package:flutter/material.dart';

import '../../core/errors/error_text.dart';
import '../../core/l10n/l10n.dart';
import '../../core/models/load.dart';
import '../../core/models/offer.dart';
import '../../core/services/load_service.dart';
import '../../core/services/offer_service.dart';
import '../../core/services/vehicle_service.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/ds/app_button.dart';
import '../../core/widgets/ds/route_ribbon.dart';
import '../../core/widgets/ds/sheet_kit.dart';
import '../../core/widgets/ds/status_badge.dart';
import '../../core/widgets/live_stream.dart';
import '../../core/widgets/logistics_labels.dart';
import '../../core/dispatch/driver_bid_sheet.dart';

/// U31: the four places a bid can be in.
enum BidGroup { waiting, countered, selected, lost }

/// Which group a bid belongs to. A confirmed bid is a won one, so it sits with Selected.
BidGroup bidGroupOf(String status) => switch (status) {
      OfferStatus.countered => BidGroup.countered,
      OfferStatus.selected || OfferStatus.confirmed => BidGroup.selected,
      OfferStatus.rejected || OfferStatus.withdrawn => BidGroup.lost,
      _ => BidGroup.waiting,
    };

/// How many bids each group holds.
Map<BidGroup, int> bidCounts(Iterable<Offer> offers) {
  final m = {for (final g in BidGroup.values) g: 0};
  for (final o in offers) {
    final g = bidGroupOf(o.status);
    m[g] = m[g]! + 1;
  }
  return m;
}

StatusTone bidTone(String status) => switch (status) {
      OfferStatus.countered => StatusTone.attention,
      OfferStatus.selected || OfferStatus.confirmed => StatusTone.success,
      OfferStatus.rejected || OfferStatus.withdrawn => StatusTone.danger,
      _ => StatusTone.progress,
    };

String _groupKey(BidGroup g) => switch (g) {
      BidGroup.waiting => 'mbWaiting',
      BidGroup.countered => 'mbCountered',
      BidGroup.selected => 'mbSelected',
      BidGroup.lost => 'mbLost',
    };

/// The driver's bids, with a chip per group (and how many are in it), the status in plain words, and the bid sheet
/// for a change or a withdraw.
class MyBidsV2 extends StatefulWidget {
  final ValueChanged<String> onOpenBooking;
  const MyBidsV2({super.key, required this.onOpenBooking});

  @override
  State<MyBidsV2> createState() => _MyBidsV2State();
}

class _MyBidsV2State extends State<MyBidsV2> {
  BidGroup? _group;

  @override
  Widget build(BuildContext context) {
    return LiveStream<List<Offer>>(
      stream: OfferService.watchMine,
      builder: (context, offers) {
        if (offers.isEmpty) return EmptyState(icon: Icons.local_offer_outlined, title: tr(context, 'noMyOffers'));
        final counts = bidCounts(offers);
        final shown = _group == null ? offers : [for (final o in offers) if (bidGroupOf(o.status) == _group) o];
        return Column(children: [
          const SizedBox(height: DsSpace.s2),
          QuickChipRow<BidGroup>(
            key: const ValueKey('mbGroups'),
            options: [for (final g in BidGroup.values) (g, '${tr(context, _groupKey(g))} (${counts[g]})')],
            selected: _group,
            clearable: true,
            onChanged: (g) => setState(() => _group = g),
          ),
          Expanded(
            child: shown.isEmpty
                ? EmptyState(icon: Icons.local_offer_outlined, title: tr(context, 'mbNoneHere'))
                : ListView.separated(
                    padding: const EdgeInsets.all(DsSpace.gutter),
                    itemCount: shown.length,
                    separatorBuilder: (_, _) => const SizedBox(height: DsSpace.s3),
                    itemBuilder: (context, i) => _BidCard(key: ValueKey(shown[i].id), offer: shown[i], onOpenBooking: widget.onOpenBooking),
                  ),
          ),
        ]);
      },
    );
  }
}

class _BidCard extends StatefulWidget {
  final Offer offer;
  final ValueChanged<String> onOpenBooking;
  const _BidCard({super.key, required this.offer, required this.onOpenBooking});

  @override
  State<_BidCard> createState() => _BidCardState();
}

class _BidCardState extends State<_BidCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on OfferStateException {
      if (mounted) showSnack(context, tr(context, 'offerChanged'));
    } catch (e) {
      if (mounted) showSnack(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _change() => _run(() async {
        final o = widget.offer;
        final Load? load = await LoadService.watchById(o.loadId).first;
        final vehicles = await VehicleService.fetchMyActive();
        if (!mounted) return;
        final matching = vehicles.where((v) => v.id == o.vehicleId);
        if (load == null || matching.isEmpty) return showSnack(context, tr(context, 'offerChanged'));
        await showDriverBidSheet(context, load: load, vehicle: matching.first, pickupKm: o.pickupKm, existing: o);
      });

  @override
  Widget build(BuildContext context) {
    final o = widget.offer;
    final c = context.ds;
    final busy = _busy;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Align(alignment: AlignmentDirectional.centerStart, child: StatusBadge(label: offerStatusLabel(context, o.status), tone: bidTone(o.status))),
        const SizedBox(height: DsSpace.s2),
        RouteRibbon(from: o.pickup, to: o.drop),
        const SizedBox(height: DsSpace.s2),
        Text('${o.vehicleNumber} • ${vehicleTypeLabel(context, o.vehicleType)}', style: DsType.bodySmall.copyWith(color: c.textMuted)),
        const SizedBox(height: DsSpace.s1),
        Text(formatPaise(o.pricePaise), key: ValueKey('mbPrice_${o.id}'), style: DsType.headline.copyWith(color: c.textStrong)),
        if (o.etaMinutes != null) Text(trf(context, 'uxEtaMin', {'n': o.etaMinutes!}), style: DsType.bodySmall.copyWith(color: c.textMuted)),
        if (o.counterPaise != null && o.status == OfferStatus.countered)
          Text(trf(context, 'counterOf', {'amount': formatPaise(o.counterPaise!)}), key: ValueKey('mbCounter_${o.id}'), style: DsType.label.copyWith(color: c.warning)),
        const SizedBox(height: DsSpace.s3),
        if (o.status == OfferStatus.selected)
          AppButton(key: ValueKey('confirm_${o.id}'), label: tr(context, 'confirmBooking'), big: true, loading: busy, onPressed: busy ? null : () => _run(() async => widget.onOpenBooking(await OfferService.confirm(o)))),
        if (o.status == OfferStatus.countered) ...[
          AppButton(key: ValueKey('acceptCounter_${o.id}'), label: tr(context, 'acceptCounter'), big: true, loading: busy, onPressed: busy ? null : () => _run(() => OfferService.acceptCounter(o.id))),
          const SizedBox(height: DsSpace.s2),
        ],
        if (o.isOpen && o.status != OfferStatus.selected) AppButton(key: ValueKey('change_${o.id}'), label: tr(context, 'mbChange'), kind: AppButtonKind.secondary, onPressed: busy ? null : _change),
        if (o.status == OfferStatus.selected)
          Padding(
            padding: const EdgeInsets.only(top: DsSpace.s2),
            child: AppButton(key: ValueKey('withdraw_${o.id}'), label: tr(context, 'withdrawOffer'), kind: AppButtonKind.tertiary, onPressed: busy ? null : () => _run(() => OfferService.withdraw(o.id))),
          ),
        if (o.status == OfferStatus.confirmed && o.bookingId != null) AppButton(label: tr(context, 'viewTrip'), kind: AppButtonKind.secondary, onPressed: () => widget.onOpenBooking(o.bookingId!)),
      ]),
    );
  }
}
