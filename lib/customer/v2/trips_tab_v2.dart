import 'package:flutter/material.dart';

import '../../core/constants/logistics.dart';
import '../../core/l10n/l10n.dart';
import '../../core/models/booking.dart';
import '../../core/models/load.dart';
import '../../core/services/booking_service.dart';
import '../../core/services/load_service.dart';
import '../../core/services/pricing_service.dart';
import '../../core/services/server_clock.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/ds/app_button.dart';
import '../../core/widgets/ds/status_badge.dart';
import '../../core/widgets/ds/sheet_kit.dart';
import '../../core/widgets/live_stream.dart';
import '../../core/widgets/logistics_labels.dart';
import '../../core/widgets/paged_live_stream.dart';
import 'trips_model.dart';

/// U23: the Trips tab of the new customer app: Active, Upcoming and Past, with the loads still waiting for a driver
/// in Active (or Upcoming for an advance booking) and "Book again" on past ones. Loading, empty, error and offline
/// states come from the shared live-list widgets.
class TripsTabV2 extends StatefulWidget {
  final PagedStreamFactory<Booking>? bookings;
  final Stream<List<Load>> Function()? loads;
  final ValueChanged<String> onOpenBooking;
  final ValueChanged<String> onOpenLoad;
  final ValueChanged<TripItem> onBookAgain;
  final VoidCallback? onBook;
  final DateTime Function()? now;

  const TripsTabV2({super.key, this.bookings, this.loads, required this.onOpenBooking, required this.onOpenLoad, required this.onBookAgain, this.onBook, this.now});

  @override
  State<TripsTabV2> createState() => _TripsTabV2State();
}

class _TripsTabV2State extends State<TripsTabV2> {
  TripSegment _segment = TripSegment.active;

  String _segmentLabel(TripSegment s) => tr(context, switch (s) {
        TripSegment.active => 'trActive',
        TripSegment.upcoming => 'trUpcoming',
        TripSegment.past => 'trPast',
      });

  String _emptyKey(TripSegment s) => switch (s) {
        TripSegment.active => 'trEmptyActive',
        TripSegment.upcoming => 'trEmptyUpcoming',
        TripSegment.past => 'trEmptyPast',
      };

  Widget _tile(TripItem item) {
    final c = context.ds;
    final b = item.booking, l = item.load;
    final StatusTone tone;
    final String status;
    if (b != null) {
      status = bookingStatusLabel(context, b.status);
      tone = b.status == BookingStatus.delivered ? StatusTone.success : (b.status == BookingStatus.cancelled ? StatusTone.danger : StatusTone.progress);
    } else if (l!.isOpen) {
      status = tr(context, 'trWaitingDrivers');
      tone = StatusTone.attention;
    } else {
      status = tr(context, 'trLoadClosed');
      tone = StatusTone.neutral;
    }
    final price = b?.agreedFarePaise ?? b?.fareEstimate ?? (l?.budget == null ? null : (l!.budget! * 100).round());
    final when = item.when;
    final past = _segment == TripSegment.past;
    return Padding(
      key: ValueKey('trip_${item.id}'),
      padding: const EdgeInsets.only(bottom: DsSpace.s3),
      child: AppCard(
        onTap: past ? null : () => b != null ? widget.onOpenBooking(b.id) : widget.onOpenLoad(l!.id),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${item.pickup} → ${item.drop}', maxLines: 2, overflow: TextOverflow.ellipsis, style: DsType.subtitle.copyWith(color: c.textStrong)),
          const SizedBox(height: DsSpace.s1),
          Wrap(spacing: DsSpace.s2, runSpacing: DsSpace.s1, crossAxisAlignment: WrapCrossAlignment.center, children: [
            StatusBadge(label: status, tone: tone),
            if (when != null) Text(formatDate(when), style: DsType.bodySmall.copyWith(color: c.textMuted)),
            if (price != null) Text(formatPaise(price), style: DsType.bodySmall.copyWith(color: c.textStrong)),
          ]),
          const SizedBox(height: DsSpace.s3),
          if (past)
            AppButton(key: ValueKey('again_${item.id}'), label: tr(context, 'hvAgain'), kind: AppButtonKind.secondary, icon: Icons.replay_rounded, onPressed: () => widget.onBookAgain(item))
          else
            AppButton(key: ValueKey('open_${item.id}'), label: tr(context, 'hvOpen'), kind: AppButtonKind.secondary, onPressed: () => b != null ? widget.onOpenBooking(b.id) : widget.onOpenLoad(l!.id)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(DsSpace.gutter, DsSpace.s4, DsSpace.gutter, DsSpace.s2),
          child: Semantics(header: true, child: Text(tr(context, 'hvTabTrips'), style: DsType.headline.copyWith(color: c.textStrong))),
        ),
        QuickChipRow<TripSegment>(
          options: [for (final s in TripSegment.values) (s, _segmentLabel(s))],
          selected: _segment,
          onChanged: (v) => setState(() => _segment = v ?? _segment),
        ),
        Expanded(
          child: PagedLiveStream<Booking>(
            stream: widget.bookings ?? BookingService.watchForCustomerPage,
            builder: (context, bookings, loadMore) => LiveStream<List<Load>>(
              stream: widget.loads ?? LoadService.watchMine,
              loadingBuilder: (_) => const Padding(padding: EdgeInsets.all(DsSpace.gutter), child: SkeletonList()),
              builder: (context, loads) {
                final now = widget.now?.call() ?? ServerClock.now();
                final buckets = TripBuckets.compute(bookings: bookings, loads: loads, now: now, rules: PricingService.config.schedule);
                final list = buckets.of(_segment);
                if (list.isEmpty) {
                  return EmptyState(
                    icon: Icons.local_shipping_outlined,
                    illustration: null,
                    title: tr(context, _emptyKey(_segment)),
                    action: _segment == TripSegment.active && widget.onBook != null ? AppButton(key: const ValueKey('tripsBook'), label: tr(context, 'hvBookBig'), expand: false, onPressed: widget.onBook) : null,
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(DsSpace.gutter),
                  itemCount: list.length + (loadMore == null ? 0 : 1),
                  itemBuilder: (context, i) => i < list.length ? _tile(list[i]) : loadMore!,
                );
              },
            ),
          ),
        ),
      ]),
    );
  }
}
