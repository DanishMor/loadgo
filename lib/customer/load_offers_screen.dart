import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/load.dart';
import '../core/models/offer.dart';
import '../core/services/offer_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';
import '../core/widgets/logistics_labels.dart';

/// "Offers (n)" button on an open load in My Loads.
class LoadOffersButton extends StatelessWidget {
  final Load load;
  final ValueChanged<String> onOpenBooking;

  const LoadOffersButton({super.key, required this.load, required this.onOpenBooking});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Offer>>(
      stream: OfferService.watchForLoad(load.id),
      builder: (context, snap) {
        final open = (snap.data ?? const []).where((o) => o.isOpen).length;
        return SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            key: ValueKey('offers_${load.id}'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => LoadOffersScreen(load: load, onOpenBooking: onOpenBooking)),
            ),
            icon: Badge(isLabelVisible: open > 0, label: Text('$open'), child: const Icon(Icons.local_offer_outlined)),
            label: Text(trf(context, 'offersCount', {'n': open})),
          ),
        );
      },
    );
  }
}

/// Customer compares drivers' offers for one load: select one, counter once,
/// or reject. The selected driver confirms to create the booking.
class LoadOffersScreen extends StatelessWidget {
  final Load load;
  final ValueChanged<String> onOpenBooking;

  const LoadOffersScreen({super.key, required this.load, required this.onOpenBooking});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        title: RouteText(pickup: load.pickup, drop: load.drop),
      ),
      body: SafeArea(
        child: LiveStream<List<Offer>>(
          stream: () => OfferService.watchForLoad(load.id),
          builder: (context, offers) {
            if (offers.isEmpty) {
              return EmptyState(icon: Icons.local_offer_outlined, title: tr(context, 'noOffers'));
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
              children: [
                if (load.estimate != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('${tr(context, 'fareEstimate')}: ${formatPaise(load.estimate!.total)}',
                        style: TextStyle(color: AppColors.muted)),
                  ),
                for (final o in offers) ...[
                  _CustomerOfferCard(key: ValueKey(o.id), offer: o, onOpenBooking: onOpenBooking),
                  const SizedBox(height: 12),
                ],
                Text(tr(context, 'selectOfferNote'), style: TextStyle(color: AppColors.faint, fontSize: 12)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CustomerOfferCard extends StatefulWidget {
  final Offer offer;
  final ValueChanged<String> onOpenBooking;
  const _CustomerOfferCard({super.key, required this.offer, required this.onOpenBooking});

  @override
  State<_CustomerOfferCard> createState() => _CustomerOfferCardState();
}

class _CustomerOfferCardState extends State<_CustomerOfferCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on OfferStateException {
      if (mounted) showSnack(context, tr(context, 'offerChanged'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _counter() async {
    final paise = await askPricePaise(
      context,
      title: tr(context, 'counterOffer'),
      label: tr(context, 'counterPrice'),
      note: tr(context, 'counterOnce'),
    );
    if (paise != null) await _run(() => OfferService.counter(widget.offer.id, paise));
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.offer;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(o.driverName.isEmpty ? tr(context, 'driver') : o.driverName,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.title)),
              ),
              StatusChip(label: offerStatusLabel(context, o.status), color: offerStatusColor(o.status)),
            ],
          ),
          Text('${o.vehicleNumber} • ${vehicleTypeLabel(context, o.vehicleType)}', style: TextStyle(color: AppColors.muted)),
          if (o.isCompanyBid)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(spacing: 6, children: [
                StatusChip(key: ValueKey('companyChip_${o.id}'), label: tr(context, 'fleetOwner'), color: AppColors.primary),
                if (o.companyVerified) StatusChip(key: ValueKey('verifiedChip_${o.id}'), label: tr(context, 'trpVerified'), color: AppColors.success),
              ]),
            ),
          const SizedBox(height: 6),
          Text(formatPaise(o.pricePaise),
              key: ValueKey('price_${o.id}'),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.title)),
          if (o.originalPaise != o.pricePaise)
            Text(trf(context, 'firstOffer', {'amount': formatPaise(o.originalPaise)}), style: TextStyle(color: AppColors.faint)),
          if (o.status == OfferStatus.countered)
            Text(trf(context, 'counterOf', {'amount': formatPaise(o.counterPaise!)}),
                style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (o.status == OfferStatus.pending)
                FilledButton(
                  key: ValueKey('select_${o.id}'),
                  onPressed: _busy ? null : () => _run(() => OfferService.select(o)),
                  child: Text(tr(context, 'selectOffer')),
                ),
              if (o.canCounter)
                OutlinedButton(
                  key: ValueKey('counter_${o.id}'),
                  onPressed: _busy ? null : _counter,
                  child: Text(tr(context, 'counterOffer')),
                ),
              if (o.status == OfferStatus.pending || o.status == OfferStatus.selected)
                TextButton(
                  key: ValueKey('reject_${o.id}'),
                  onPressed: _busy ? null : () => _run(() => OfferService.reject(o.id)),
                  style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                  child: Text(tr(context, 'rejectOffer')),
                ),
              if (o.status == OfferStatus.confirmed && o.bookingId != null)
                OutlinedButton(onPressed: () => widget.onOpenBooking(o.bookingId!), child: Text(tr(context, 'viewBooking'))),
            ],
          ),
        ],
      ),
    );
  }
}
