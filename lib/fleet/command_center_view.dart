import 'package:flutter/material.dart';

import '../core/fleet/command_center.dart';
import '../core/fleet/fleet_logic.dart';
import '../core/l10n/l10n.dart';
import '../core/models/booking.dart';
import '../core/models/fleet.dart';
import '../core/models/offer.dart';
import '../core/models/vehicle.dart';
import '../core/theme/design_tokens.dart';
import '../core/transporter/transporter_logic.dart';
import '../core/widgets/common.dart';
import '../core/widgets/ds/route_ribbon.dart';
import '../core/widgets/ds/skeleton.dart';
import '../core/widgets/ds/status_badge.dart';
import '../core/widgets/live_stream.dart' show ErrorState;
import '../core/widgets/logistics_labels.dart';

/// E23 (flag fleetCommand): the transporter's command center: what every truck is doing, what needs attention,
/// open bids, money still owed and how much the fleet is used. Takes the lists the dashboard already has (its
/// streams are broadcast and would not replay to a late listener) plus the books and the newest 20 bids.
class FleetCommandCenter extends StatelessWidget {
  final List<Vehicle> vehicles;
  final List<Booking> bookings;
  final List<FleetMember> members;
  final Stream<List<TripAccount>> accounts;
  final Stream<List<Offer>> bids;
  final ValueChanged<String>? onOpenBooking;
  final VoidCallback? onOpenBids;
  final VoidCallback? onOpenBooks;
  final DateTime Function() now;

  const FleetCommandCenter({
    super.key,
    required this.vehicles,
    required this.bookings,
    required this.members,
    required this.accounts,
    required this.bids,
    this.onOpenBooking,
    this.onOpenBids,
    this.onOpenBooks,
    this.now = DateTime.now,
  });

  static StatusTone tone(VehicleState s) => switch (s) {
        VehicleState.onTrip => StatusTone.progress,
        VehicleState.assigned => StatusTone.progress,
        VehicleState.available => StatusTone.success,
        VehicleState.blocked => StatusTone.attention,
        VehicleState.off => StatusTone.neutral,
      };

  String _alertText(BuildContext context, FleetAlert a) => switch (a.kind) {
        AlertKind.papersExpired => trf(context, 'ccAlertExpired', {'vehicle': a.subject, 'n': a.count}),
        AlertKind.counterOffer => trf(context, 'ccAlertCounter', {'route': a.subject}),
        AlertKind.papersSoon => trf(context, 'ccAlertSoon', {'vehicle': a.subject, 'n': a.count}),
        AlertKind.idleTruck => trf(context, 'ccAlertIdle', {'vehicle': a.subject, 'n': a.count}),
        AlertKind.partyDue => trf(context, 'ccAlertDue', {'party': a.subject, 'amount': formatPaise(a.count)}),
      };

  static IconData _alertIcon(AlertKind k) => switch (k) {
        AlertKind.papersExpired => Icons.error_outline_rounded,
        AlertKind.counterOffer => Icons.gavel_rounded,
        AlertKind.papersSoon => Icons.schedule_rounded,
        AlertKind.idleTruck => Icons.hourglass_empty_rounded,
        AlertKind.partyDue => Icons.account_balance_wallet_outlined,
      };

  @override
  Widget build(BuildContext context) => StreamBuilder<List<TripAccount>>(
        stream: accounts,
        builder: (context, as) => StreamBuilder<List<Offer>>(
          stream: bids,
          builder: (context, os) {
            if (os.hasError) return ErrorState(compact: true, error: os.error);
            if (!os.hasData) return const SkeletonList(key: ValueKey('ccSkeleton'), count: 3, padding: EdgeInsets.zero);
            return _body(context, vehicles, bookings, members, as.data ?? const [], os.data!);
          },
        ),
      );

  Widget _body(BuildContext context, List<Vehicle> vs, List<Booking> bs, List<FleetMember> ms, List<TripAccount> as, List<Offer> os) {
    final c = context.ds;
    final at = now();
    final analytics = FleetAnalytics.from(vehicles: vs, bookings: bs, expenses: const [], members: ms, now: at);
    final books = TransporterBooks.from(as);
    final cc = CommandCenter.compute(
      vehicles: vs,
      bookings: bs,
      bids: os,
      idleDays: {for (final s in analytics.vehicles) s.vehicle.id: s.idleDays},
      dues: [for (final p in books.parties) (name: p.partyName.isEmpty ? p.partyId : p.partyName, duePaise: p.duePaise)],
      now: at,
    );
    final counts = cc.counts;
    final due = books.parties.fold<int>(0, (a, p) => a + (p.duePaise > 0 ? p.duePaise : 0));
    Widget title(String key) => Padding(
          padding: const EdgeInsets.only(top: DsSpace.s4, bottom: DsSpace.s2),
          child: Semantics(header: true, child: Text(tr(context, key), style: DsType.subtitle.copyWith(color: c.textStrong))),
        );
    return Column(key: const ValueKey('ccBody'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(header: true, child: Text(tr(context, 'ccTitle'), style: DsType.title.copyWith(color: c.textStrong))),
      const SizedBox(height: DsSpace.s2),
      Wrap(spacing: DsSpace.s2, runSpacing: DsSpace.s2, children: [
        for (final s in VehicleState.values)
          if ((counts[s] ?? 0) > 0) StatusBadge(key: ValueKey('ccCount_${s.name}'), label: '${tr(context, 'ccState_${s.name}')}: ${counts[s]}', tone: tone(s)),
        StatusBadge(key: const ValueKey('ccUse'), label: trf(context, 'ccUse', {'p': (analytics.utilisation * 100).round()}), tone: StatusTone.neutral, icon: Icons.speed_rounded),
      ]),
      title('ccAlerts'),
      if (cc.alerts.isEmpty)
        Text(tr(context, 'ccNoAlerts'), key: const ValueKey('ccNoAlerts'), style: DsType.bodySmall.copyWith(color: c.textMuted))
      else
        for (final a in cc.alerts)
          Padding(
            key: ValueKey('ccAlert_${a.kind.name}_${a.subject}'),
            padding: const EdgeInsets.only(bottom: DsSpace.s2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(_alertIcon(a.kind), size: 20, color: a.kind.index < 2 ? c.error : c.warning),
              const SizedBox(width: DsSpace.s2),
              Expanded(child: Text(_alertText(context, a), style: DsType.bodySmall.copyWith(color: c.text))),
            ]),
          ),
      title('ccBoard'),
      if (cc.board.isEmpty) Text(tr(context, 'ccNoVehicles'), key: const ValueKey('ccNoVehicles'), style: DsType.bodySmall.copyWith(color: c.textMuted)),
      for (final v in cc.board)
        Padding(
          padding: const EdgeInsets.only(bottom: DsSpace.s2),
          child: AppCard(
            key: ValueKey('ccVehicle_${v.vehicle.id}'),
            onTap: v.booking == null || onOpenBooking == null ? null : () => onOpenBooking!(v.booking!.id),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: DsSpace.s2, runSpacing: DsSpace.s1, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('${v.vehicle.number} · ${v.vehicle.type}', style: DsType.subtitle.copyWith(color: c.textStrong)),
                StatusBadge(label: v.booking != null && v.state == VehicleState.onTrip ? bookingStatusLabel(context, v.booking!.status) : tr(context, 'ccState_${v.state.name}'), tone: tone(v.state)),
              ]),
              if (v.booking != null) ...[
                const SizedBox(height: DsSpace.s2),
                RouteRibbon(from: v.booking!.pickup, to: v.booking!.drop),
              ],
            ]),
          ),
        ),
      title('ccBids'),
      if (cc.pendingBids.isEmpty)
        Text(tr(context, 'ccNoBids'), key: const ValueKey('ccNoBids'), style: DsType.bodySmall.copyWith(color: c.textMuted))
      else ...[
        for (final o in cc.pendingBids.take(3))
          Padding(
            key: ValueKey('ccBid_${o.id}'),
            padding: const EdgeInsets.only(bottom: DsSpace.s1),
            child: Text('${o.pickup} → ${o.drop} · ${formatPaise(o.counterPaise ?? o.pricePaise)}', style: DsType.bodySmall.copyWith(color: c.text)),
          ),
        if (onOpenBids != null)
          Align(alignment: AlignmentDirectional.centerStart, child: TextButton(key: const ValueKey('ccAllBids'), onPressed: onOpenBids, child: Text(trf(context, 'ccAllBids', {'n': cc.pendingBids.length})))),
      ],
      title('ccDues'),
      Text(due > 0 ? trf(context, 'ccDueTotal', {'amount': formatPaise(due)}) : tr(context, 'tbNoDue'), key: const ValueKey('ccDue'), style: DsType.body.copyWith(color: due > 0 ? c.warning : c.textMuted)),
      if (due > 0 && onOpenBooks != null)
        Align(alignment: AlignmentDirectional.centerStart, child: TextButton(key: const ValueKey('ccBooks'), onPressed: onOpenBooks, child: Text(tr(context, 'ccOpenBooks')))),
    ]);
  }
}
