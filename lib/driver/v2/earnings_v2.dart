import 'package:flutter/material.dart';

import '../../core/analytics/earnings_breakdown.dart';
import '../../core/features/features.dart';
import '../../core/l10n/l10n.dart';
import '../../core/models/booking.dart';
import '../../core/models/earnings.dart';
import '../../core/models/ledger_entry.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/trip/trip_history_screen.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feature_gate.dart';
import '../../core/widgets/ds/status_badge.dart';
import '../../core/widgets/mini_bars.dart';
import '../driver_rewards_screen.dart';

/// Where a delivered trip's money is, in the order it moves.
enum MoneyStage { waitCustomer, confirmReceived, inWallet }

/// A delivered trip's money stage: nothing paid yet, paid by the customer (the driver confirms), or confirmed.
MoneyStage moneyStageOf(Booking b) => switch (b.paymentStatus) {
      PaymentStatus.driverConfirmed => MoneyStage.inWallet,
      PaymentStatus.customerMarkedPaid => MoneyStage.confirmReceived,
      _ => MoneyStage.waitCustomer,
    };

/// What the delivered trips hold in each stage, in paise (the bill amount, 0 when the trip has none).
Map<MoneyStage, int> moneyByStage(Iterable<Booking> delivered) {
  final m = {for (final s in MoneyStage.values) s: 0};
  for (final b in delivered) {
    final s = moneyStageOf(b);
    m[s] = m[s]! + (b.billAmountPaise ?? 0);
  }
  return m;
}

String moneyStageKey(MoneyStage s) => switch (s) {
      MoneyStage.waitCustomer => 'epWaitCustomer',
      MoneyStage.confirmReceived => 'epConfirmReceived',
      MoneyStage.inWallet => 'epInWallet',
    };

StatusTone moneyTone(MoneyStage s) => switch (s) {
      MoneyStage.waitCustomer => StatusTone.attention,
      MoneyStage.confirmReceived => StatusTone.progress,
      MoneyStage.inWallet => StatusTone.success,
    };

/// U33: the Earnings tab with the day's money first and a clear line for where the rest of the money is.
class EarningsV2 extends StatelessWidget {
  final List<Booking> list;
  final Stream<List<Booking>> Function() bookings;
  final ValueChanged<String> onOpenTrip;
  final DateTime now;

  const EarningsV2({super.key, required this.list, required this.bookings, required this.onOpenTrip, required this.now});

  Widget _stat(BuildContext context, String label, String value) {
    final c = context.ds;
    return Expanded(
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: DsType.bodySmall.copyWith(color: c.textMuted)),
          const SizedBox(height: DsSpace.s1),
          Text(value, style: DsType.title.copyWith(color: c.textStrong)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final e = EarningsSummary.from(list, now);
    final days = EarningsBreakdown.from(list, now);
    final money = moneyByStage(e.delivered);
    return ListView(
      padding: const EdgeInsets.fromLTRB(DsSpace.gutter, DsSpace.s4, DsSpace.gutter, DsSpace.s8),
      children: [
        Text(tr(context, 'earnings'), style: DsType.headline.copyWith(color: c.textStrong)),
        const SizedBox(height: DsSpace.s3),
        FeatureGate(
          featureKey: FeatureKey.driverRewards,
          child: ListTile(
            key: const ValueKey('openRewards'),
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.card_giftcard_rounded, color: c.primary),
            title: Text(tr(context, 'tipsBonusesPlan'), style: DsType.label),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DriverRewardsScreen())),
          ),
        ),
        Container(
          key: const ValueKey('epHero'),
          padding: const EdgeInsets.all(DsSpace.s5),
          decoration: BoxDecoration(gradient: const LinearGradient(colors: DsHero.colors), borderRadius: DsRadius.all(DsRadius.lg)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(context, 'ehToday'), style: DsType.body.copyWith(color: c.onPrimary.withValues(alpha: 0.8))),
            const SizedBox(height: DsSpace.s1),
            Text(formatPaise(days.todayPaise), style: DsType.display.copyWith(color: c.onPrimary)),
          ]),
        ),
        const SizedBox(height: DsSpace.s3),
        Row(children: [
          _stat(context, tr(context, 'totalEarnings'), formatRupees(e.total)),
          const SizedBox(width: DsSpace.s3),
          _stat(context, tr(context, 'thisWeek'), formatRupees(e.thisWeek)),
        ]),
        const SizedBox(height: DsSpace.s3),
        Row(children: [
          _stat(context, tr(context, 'tripsCompleted'), '${e.completedTrips}'),
          const SizedBox(width: DsSpace.s3),
          _stat(context, tr(context, 'ehLast7'), formatPaise(days.last7Paise)),
        ]),
        const SizedBox(height: DsSpace.s3),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(context, 'ehEarnByDay'), style: DsType.bodySmall.copyWith(color: c.textMuted)),
            const SizedBox(height: DsSpace.s2),
            MiniBars(
              keyPrefix: 'earnBar',
              highlight: days.last7Days.length - 1,
              bars: [for (final d in days.last7Days) MiniBar('${d.day.day}', d.paise, '${formatDate(d.day)}: ${formatPaise(d.paise)}')],
            ),
          ]),
        ),
        if (e.delivered.isNotEmpty) ...[
          const SizedBox(height: DsSpace.s4),
          Text(tr(context, 'epMoneyTitle'), style: DsType.title.copyWith(color: c.textStrong)),
          const SizedBox(height: DsSpace.s2),
          AppCard(
            key: const ValueKey('epMoney'),
            child: Column(children: [
              for (final s in MoneyStage.values)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: DsSpace.s1),
                  child: Row(children: [
                    Expanded(child: Align(alignment: AlignmentDirectional.centerStart, child: StatusBadge(label: tr(context, moneyStageKey(s)), tone: moneyTone(s)))),
                    const SizedBox(width: DsSpace.s2),
                    Text(formatPaise(money[s]!), key: ValueKey('epStage_${s.name}'), style: DsType.label.copyWith(color: c.textStrong)),
                  ]),
                ),
            ]),
          ),
        ],
        ListTile(
          key: const ValueKey('openHistory'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.history_rounded, color: c.primary),
          title: Text(tr(context, 'ehHistoryTitle'), style: DsType.label),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TripHistoryScreen(bookings: bookings, onOpen: onOpenTrip))),
        ),
        Text(tr(context, 'earningsNote'), style: DsType.caption.copyWith(color: c.textMuted)),
        const SizedBox(height: DsSpace.s5),
        Text(tr(context, 'recentTrips'), style: DsType.title.copyWith(color: c.textStrong)),
        const SizedBox(height: DsSpace.s2),
        if (e.delivered.isEmpty)
          EmptyState(icon: Icons.account_balance_wallet_outlined, title: tr(context, 'noEarningsYet'))
        else
          for (final b in e.delivered) ...[
            AppCard(
              onTap: () => onOpenTrip(b.id),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    RouteText(pickup: b.pickup, drop: b.drop, fontSize: 15),
                    const SizedBox(height: DsSpace.s1),
                    Text(formatDate(EarningsSummary.deliveredAt(b)), style: DsType.bodySmall.copyWith(color: c.textMuted)),
                    const SizedBox(height: DsSpace.s1),
                    StatusBadge(label: tr(context, moneyStageKey(moneyStageOf(b))), tone: moneyTone(moneyStageOf(b))),
                  ]),
                ),
                Text(b.budget == null ? tr(context, 'budgetNegotiable') : formatRupees(b.budget!), style: DsType.label.copyWith(color: c.success)),
              ]),
            ),
            const SizedBox(height: DsSpace.s3),
          ],
      ],
    );
  }
}
