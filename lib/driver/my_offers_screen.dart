import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/offer.dart';
import '../core/services/offer_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';
import '../core/widgets/logistics_labels.dart';

/// The driver's offers with what they can do next: withdraw, accept the
/// customer's counter, or confirm a selected offer (creates the booking).
class MyOffersScreen extends StatelessWidget {
  /// Opens a booking (the driver trip screen lives outside this folder).
  final ValueChanged<String> onOpenBooking;

  const MyOffersScreen({super.key, required this.onOpenBooking});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        title: Text(tr(context, 'myOffers'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: LiveStream<List<Offer>>(
          stream: OfferService.watchMine,
          builder: (context, offers) {
            if (offers.isEmpty) {
              return EmptyState(icon: Icons.local_offer_outlined, title: tr(context, 'noMyOffers'));
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
              itemCount: offers.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _DriverOfferCard(key: ValueKey(offers[i].id), offer: offers[i], onOpenBooking: onOpenBooking),
            );
          },
        ),
      ),
    );
  }
}

class _DriverOfferCard extends StatefulWidget {
  final Offer offer;
  final ValueChanged<String> onOpenBooking;
  const _DriverOfferCard({super.key, required this.offer, required this.onOpenBooking});

  @override
  State<_DriverOfferCard> createState() => _DriverOfferCardState();
}

class _DriverOfferCardState extends State<_DriverOfferCard> {
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

  Future<void> _confirm() => _run(() async {
        final bookingId = await OfferService.confirm(widget.offer);
        if (mounted) widget.onOpenBooking(bookingId);
      });

  @override
  Widget build(BuildContext context) {
    final o = widget.offer;
    final busy = _busy;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: RouteText(pickup: o.pickup, drop: o.drop)),
              StatusChip(label: offerStatusLabel(context, o.status), color: offerStatusColor(o.status)),
            ],
          ),
          const SizedBox(height: 6),
          Text('${o.vehicleNumber} • ${vehicleTypeLabel(context, o.vehicleType)}', style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 6),
          Text(formatPaise(o.pricePaise), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.title)),
          if (o.counterPaise != null && o.status == OfferStatus.countered)
            Text(trf(context, 'counterOf', {'amount': formatPaise(o.counterPaise!)}),
                style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (o.status == OfferStatus.selected)
                FilledButton.icon(
                  key: ValueKey('confirm_${o.id}'),
                  onPressed: busy ? null : _confirm,
                  icon: const Icon(Icons.verified_rounded),
                  label: Text(tr(context, 'confirmBooking')),
                ),
              if (o.status == OfferStatus.countered)
                FilledButton(
                  key: ValueKey('acceptCounter_${o.id}'),
                  onPressed: busy ? null : () => _run(() => OfferService.acceptCounter(o.id)),
                  child: Text(tr(context, 'acceptCounter')),
                ),
              if (o.isOpen)
                OutlinedButton(
                  key: ValueKey('withdraw_${o.id}'),
                  onPressed: busy ? null : () => _run(() => OfferService.withdraw(o.id)),
                  child: Text(tr(context, 'withdrawOffer')),
                ),
              if (o.status == OfferStatus.confirmed && o.bookingId != null)
                OutlinedButton(
                  onPressed: () => widget.onOpenBooking(o.bookingId!),
                  child: Text(tr(context, 'viewTrip')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
