import 'package:flutter/material.dart';

import '../core/analytics/earnings_breakdown.dart';
import '../core/models/booking.dart';
import '../core/models/earnings.dart';
import '../core/widgets/common.dart';
import '../core/l10n/l10n.dart';
import '../core/widgets/feature_gate.dart';
import '../core/features/features.dart';
import '../core/trip/trip_history_screen.dart';
import '../core/widgets/live_stream.dart';
import '../core/widgets/mini_bars.dart';
import 'driver_rewards_screen.dart';
import '../core/services/features_service.dart';
import 'v2/earnings_v2.dart';
import '../core/theme/design_tokens.dart';

/// Driver "Earnings" tab: totals from delivered trips plus recent payouts.
class EarningsView extends StatelessWidget {
  final StreamFactory<List<Booking>> bookings;
  final ValueChanged<String> onOpenTrip;

  /// Injectable clock for tests.
  final DateTime Function() now;

  const EarningsView({super.key, required this.bookings, required this.onOpenTrip, this.now = DateTime.now});

  Widget _stat(String label, String value, {bool highlight = false}) => Expanded(
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: DsStyle.t14w400.copyWith(color: AppColors.muted)),
              const SizedBox(height: 6),
              Text(value,
                  style: DsStyle.t24w700.copyWith(color: highlight ? AppColors.primary : AppColors.title)),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LiveStream<List<Booking>>(
        stream: bookings,
        builder: (context, list) {
          if (FeaturesService.isOn(FeatureKey.uiV2)) return EarningsV2(list: list, bookings: bookings, onOpenTrip: onOpenTrip, now: now());
          final e = EarningsSummary.from(list, now());
          final days = EarningsBreakdown.from(list, now());
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
            children: [
              Text(tr(context, 'earnings'),
                  style: DsStyle.t24w700.copyWith(color: AppColors.title)),
              const SizedBox(height: 16),
              FeatureGate(
                featureKey: FeatureKey.driverRewards,
                child: ListTile(
                  key: const ValueKey('openRewards'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.card_giftcard_rounded, color: AppColors.primary),
                  title: Text(tr(context, 'tipsBonusesPlan'), style: DsStyle.w700),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DriverRewardsScreen())),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: DsHero.colors),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(context, 'totalEarnings'), style: DsStyle.inherit.copyWith(color: Colors.white70)),
                    const SizedBox(height: 6),
                    Text(formatRupees(e.total),
                        style: DsStyle.t32w700.copyWith(color: Colors.white)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _stat(tr(context, 'thisWeek'), formatRupees(e.thisWeek), highlight: true),
                  const SizedBox(width: 12),
                  _stat(tr(context, 'tripsCompleted'), '${e.completedTrips}'),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _stat(tr(context, 'ehToday'), formatPaise(days.todayPaise)),
                  const SizedBox(width: 12),
                  _stat(tr(context, 'ehLast7'), formatPaise(days.last7Paise)),
                ],
              ),
              const SizedBox(height: 4),
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(context, 'ehEarnByDay'), style: DsStyle.t14w400.copyWith(color: AppColors.muted)),
                  const SizedBox(height: 10),
                  MiniBars(
                    keyPrefix: 'earnBar',
                    highlight: days.last7Days.length - 1,
                    bars: [for (final d in days.last7Days) MiniBar('${d.day.day}', d.paise, '${formatDate(d.day)}: ${formatPaise(d.paise)}')],
                  ),
                ]),
              ),
              ListTile(
                key: const ValueKey('openHistory'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history_rounded, color: AppColors.primary),
                title: Text(tr(context, 'ehHistoryTitle'), style: DsStyle.w700),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TripHistoryScreen(bookings: bookings, onOpen: onOpenTrip))),
              ),
              const SizedBox(height: 8),
              Text(tr(context, 'earningsNote'), style: DsStyle.t12w400.copyWith(color: AppColors.faint)),
              const SizedBox(height: 20),
              Text(tr(context, 'recentTrips'),
                  style: DsStyle.t18w700.copyWith(color: AppColors.title)),
              const SizedBox(height: 10),
              if (e.delivered.isEmpty)
                EmptyState(icon: Icons.account_balance_wallet_outlined, title: tr(context, 'noEarningsYet'), subtitle: tr(context, 'frEarningsSub'))
              else
                for (final b in e.delivered) ...[
                  AppCard(
                    onTap: () => onOpenTrip(b.id),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              RouteText(pickup: b.pickup, drop: b.drop, fontSize: 15),
                              const SizedBox(height: 4),
                              Text(formatDate(EarningsSummary.deliveredAt(b)),
                                  style: DsStyle.t14w400.copyWith(color: AppColors.muted)),
                            ],
                          ),
                        ),
                        Text(b.budget == null ? tr(context, 'budgetNegotiable') : formatRupees(b.budget!),
                            style: DsStyle.w700.copyWith(color: AppColors.success)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
            ],
          );
        },
      ),
    );
  }
}

/// Today's earnings figure for the Driver Home hero card.
class TodayEarningsText extends StatelessWidget {
  final Stream<List<Booking>> bookings;
  const TodayEarningsText({super.key, required this.bookings});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Booking>>(
      stream: bookings,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(error: snap.error);
        final today = EarningsSummary.from(snap.data ?? const [], DateTime.now()).today;
        return Text(formatRupees(today),
            style: DsStyle.t32w700.copyWith(color: Colors.white));
      },
    );
  }
}
