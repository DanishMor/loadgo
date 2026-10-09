import '../core/errors/error_text.dart';
import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/booking.dart';
import '../core/models/driver_extras.dart';
import '../core/services/booking_service.dart';
import '../core/services/driver_extras_service.dart';
import '../core/services/pricing_service.dart';
import '../core/services/user_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

/// Driver > Earnings > "Tips, bonuses and plan": tips received, incentive
/// targets with progress and a claim button, and the Free / Pro plan.
/// Everything here is a record; LoadGo pays bonuses by hand for now.
class DriverRewardsScreen extends StatefulWidget {
  const DriverRewardsScreen({super.key});

  @override
  State<DriverRewardsScreen> createState() => _DriverRewardsScreenState();
}

class _DriverRewardsScreenState extends State<DriverRewardsScreen> {
  late final Stream<List<Booking>> _bookings = BookingService.watchForDriver().asBroadcastStream();
  late final Stream<List<Incentive>> _incentives = DriverExtrasService.watchIncentives().asBroadcastStream();
  late final Stream<List<IncentiveClaim>> _claims = DriverExtrasService.watchMyClaims().asBroadcastStream();
  late final Stream<List<Tip>> _tips = DriverExtrasService.watchMyTips().asBroadcastStream();
  late final Stream<Map<String, dynamic>> _user = UserService.watchUser().asBroadcastStream();
  List<Booking> _lastBookings = const [];

  Future<void> _claim(Incentive i) async {
    try {
      await DriverExtrasService.claim(i, _lastBookings);
      if (mounted) showSnack(context, tr(context, 'claimSent'));
    } on ClaimException catch (e) {
      if (mounted) showSnack(context, tr(context, e.reason == 'already' ? 'claimAlready' : 'claimNotReached'));
    } catch (error) {
      if (mounted) showSnack(context, errorText(context, error));
    }
  }

  Future<void> _requestPro() async {
    try {
      await DriverExtrasService.requestPro();
      if (mounted) showSnack(context, tr(context, 'planRequested'));
    } on ClaimException {
      if (mounted) showSnack(context, tr(context, 'planAlreadyRequested'));
    } catch (error) {
      if (mounted) showSnack(context, errorText(context, error));
    }
  }

  Widget _section(String key) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(tr(context, key), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.title)),
      );

  Widget _planCard() {
    final cfg = PricingService.config;
    return LiveStream<Map<String, dynamic>>(
      stream: () => _user,
      compact: true,
      builder: (context, user) {
        final pro = DriverPlan.isPro(user, DateTime.now());
        return AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(pro ? Icons.workspace_premium_rounded : Icons.person_outline_rounded, color: pro ? AppColors.warning : AppColors.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tr(context, pro ? 'planPro' : 'planFree'),
                    key: const ValueKey('currentPlan'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
            ]),
            const SizedBox(height: 8),
            Text(trf(context, 'planCommissions', {'free': formatNum(cfg.commissionPercent), 'pro': formatNum(cfg.proCommissionPercent)}),
                style: TextStyle(color: AppColors.muted)),
            if (!pro)
              StreamBuilder<Map<String, dynamic>?>(
                stream: DriverExtrasService.watchMyPlanRequest(),
                builder: (context, snap) {
                  final status = snap.data?['status'];
                  return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: status == DriverPlan.requestPending
                        ? Text(tr(context, 'planPending'), key: const ValueKey('planPending'), style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700))
                        : FilledButton.tonal(key: const ValueKey('requestPro'), onPressed: _requestPro, child: Text(tr(context, 'planRequestPro'))),
                  );
                },
              ),
            const SizedBox(height: 6),
            Text(tr(context, 'planNote'), style: TextStyle(color: AppColors.faint, fontSize: 12)),
          ]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.background, title: Text(tr(context, 'tipsBonusesPlan'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 30), children: [
        _planCard(),
        _section('incentivesTitle'),
        LiveStream<List<Booking>>(
          stream: () => _bookings,
          compact: true,
          builder: (context, bookings) {
            _lastBookings = bookings;
            return LiveStream<List<IncentiveClaim>>(
              stream: () => _claims,
              compact: true,
              builder: (context, claims) => LiveStream<List<Incentive>>(
                stream: () => _incentives,
                compact: true,
                builder: (context, list) {
                  final now = DateTime.now();
                  final shown = [for (final i in list) if (i.isRunning(now) || claims.any((c) => c.incentiveId == i.id) || i.canClaim(bookings, now)) i];
                  if (shown.isEmpty) return Text(tr(context, 'noIncentives'), style: TextStyle(color: AppColors.muted));
                  return Column(children: [for (final i in shown) _incentiveCard(i, bookings, claims, now)]);
                },
              ),
            );
          },
        ),
        _section('tipsTitle'),
        LiveStream<List<Tip>>(
          stream: () => _tips,
          compact: true,
          builder: (context, tips) => AppCard(
            child: Row(children: [
              Expanded(child: Text(trf(context, 'tipsCount', {'n': tips.length}), style: TextStyle(color: AppColors.muted))),
              Text(formatPaise(Tip.total(tips)),
                  key: const ValueKey('tipsTotal'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _incentiveCard(Incentive i, List<Booking> bookings, List<IncentiveClaim> claims, DateTime now) {
    final done = i.tripsDone(bookings);
    final claim = claims.where((c) => c.incentiveId == i.id).firstOrNull;
    final daysLeft = i.endsAt.difference(now).inDays;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        key: ValueKey('incentive_${i.id}'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(i.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          Text(trf(context, 'incentiveRule', {'trips': i.targetTrips, 'days': i.windowDays, 'bonus': formatPaise(i.bonusPaise)}),
              style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 10),
          LinearProgressIndicator(key: ValueKey('progress_${i.id}'), value: i.progress(bookings), minHeight: 8, borderRadius: BorderRadius.circular(8)),
          const SizedBox(height: 6),
          Text(trf(context, 'incentiveProgress', {'done': done > i.targetTrips ? i.targetTrips : done, 'target': i.targetTrips}),
              key: ValueKey('progressText_${i.id}'), style: const TextStyle(fontWeight: FontWeight.w700)),
          if (daysLeft >= 0) Text(trf(context, 'incentiveDaysLeft', {'n': daysLeft}), style: TextStyle(color: AppColors.faint, fontSize: 12)),
          if (claim != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(tr(context, claim.status == IncentiveClaim.paid ? 'claimPaid' : 'claimWaiting'),
                  key: ValueKey('claimState_${i.id}'),
                  style: TextStyle(color: claim.status == IncentiveClaim.paid ? AppColors.success : AppColors.warning, fontWeight: FontWeight.w700)),
            )
          else if (i.canClaim(bookings, now))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton(key: ValueKey('claim_${i.id}'), onPressed: () => _claim(i), child: Text(tr(context, 'claimBonus'))),
            ),
        ]),
      ),
    );
  }
}
