import 'package:flutter/material.dart';

import '../../core/errors/error_text.dart';
import '../../core/l10n/l10n.dart';
import '../../core/matching/load_ranker.dart';
import '../../core/matching/nearest.dart';
import '../../core/models/load.dart';
import '../../core/services/vehicle_service.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/ds/app_button.dart';
import '../../core/widgets/ds/sheet_kit.dart';
import '../../core/dispatch/driver_bid_sheet.dart';
import 'incoming_load_screen.dart';

/// U30: how the driver's feed is ordered.
enum FeedSort { nearest, bestPay, newest }

/// The price a load offers in paise (0 when it has none); what "Best pay" sorts on.
int feedFarePaise(Load l) => cardFarePaise(l) ?? 0;

/// [items] in the order [sort] asks for. Nearest keeps the incoming order (the caller sorted it by distance).
List<NearLoad> sortFeed(List<NearLoad> items, FeedSort sort) {
  switch (sort) {
    case FeedSort.nearest:
      return items;
    case FeedSort.bestPay:
      final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
      indexed.sort((a, b) {
        final c = feedFarePaise(b.$2.load).compareTo(feedFarePaise(a.$2.load));
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
      return [for (final e in indexed) e.$2];
    case FeedSort.newest:
      final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
      int ms(Load l) => l.createdAt?.millisecondsSinceEpoch ?? 0;
      indexed.sort((a, b) {
        final c = ms(b.$2.load).compareTo(ms(a.$2.load));
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
      return [for (final e in indexed) e.$2];
  }
}

/// Sort chips and the driver's saved routes as one-tap filters.
class FeedHeaderV2 extends StatelessWidget {
  final FeedSort sort;
  final ValueChanged<FeedSort> onSort;
  final FavouriteRoute? route;
  final ValueChanged<FavouriteRoute?> onRoute;
  final Stream<List<FavouriteRoute>>? routes;

  const FeedHeaderV2({super.key, required this.sort, required this.onSort, required this.route, required this.onRoute, this.routes});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      QuickChipRow<FeedSort>(
        key: const ValueKey('fdSort'),
        options: [
          (FeedSort.nearest, tr(context, 'fdSortNearest')),
          (FeedSort.bestPay, tr(context, 'fdSortPay')),
          (FeedSort.newest, tr(context, 'fdSortNew')),
        ],
        selected: sort,
        onChanged: (v) => onSort(v ?? FeedSort.nearest),
      ),
      if (routes != null)
        StreamBuilder<List<FavouriteRoute>>(
          stream: routes,
          builder: (context, snap) {
            if (snap.hasError) return const SizedBox.shrink(); // the chips are an extra; the feed works without them
            final list = snap.data ?? const <FavouriteRoute>[];
            if (list.isEmpty) return const SizedBox.shrink();
            return QuickChipRow<String>(
              key: const ValueKey('fdRoutes'),
              options: [for (final r in list) (r.id, '${r.pickup} → ${r.drop}')],
              selected: route?.id,
              clearable: true,
              onChanged: (id) => onRoute(id == null ? null : list.firstWhere((r) => r.id == id)),
            );
          },
        ),
    ]);
  }
}

/// "Send my price" on a feed card: the truck is picked for the load, then the bid sheet opens.
class FeedBidButton extends StatefulWidget {
  final Load load;
  final int? pickupKm;
  const FeedBidButton({super.key, required this.load, this.pickupKm});

  @override
  State<FeedBidButton> createState() => _FeedBidButtonState();
}

class _FeedBidButtonState extends State<FeedBidButton> {
  bool _busy = false;

  Future<void> _open() async {
    setState(() => _busy = true);
    try {
      final all = await VehicleService.fetchMyActive();
      final v = truckForLoad(all, widget.load, now: DateTime.now());
      if (!mounted) return;
      if (v == null) return showSnack(context, tr(context, 'ilNoTruck'));
      final sent = await showDriverBidSheet(context, load: widget.load, vehicle: v, pickupKm: widget.pickupKm);
      if (mounted && sent) showSnack(context, tr(context, 'bsSent'));
    } catch (e) {
      if (mounted) showSnack(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppButton(key: ValueKey('makeOffer_${widget.load.id}'), label: tr(context, 'fdBid'), kind: AppButtonKind.secondary, onPressed: _busy ? null : _open);
}

/// The reasons a load fits this driver, or none without a context or a fitting truck.
List<MatchReason> reasonsFor(Load l, DriverContext? ctx) => ctx == null ? const [] : (LoadRanker.matchFor(l, ctx)?.reasons ?? const []);
