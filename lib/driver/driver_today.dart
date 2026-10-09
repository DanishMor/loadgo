import 'package:flutter/material.dart';

import '../core/constants/logistics.dart';
import '../core/l10n/l10n.dart';
import '../core/matching/load_ranker.dart';
import '../core/models/booking.dart';
import '../core/models/earnings.dart';
import '../core/models/load.dart';
import '../core/models/vehicle.dart';
import '../core/scheduling/schedule.dart';
import '../core/services/match_service.dart';
import '../core/services/pricing_service.dart';
import '../core/widgets/common.dart';
import 'upcoming_trips.dart';

/// The four numbers of a driver's day (MASTER-6 Task 22).
class DriverToday {
  final num earningsToday;
  final int activeTrips;
  final int upcomingCount;
  final int papersExpiring;
  final int recommendedLoads;

  const DriverToday({this.earningsToday = 0, this.activeTrips = 0, this.upcomingCount = 0, this.papersExpiring = 0, this.recommendedLoads = 0});

  /// Papers running out within this many days count on the card.
  static const paperDays = 14;

  /// [ctx] is null before it has loaded or when the driver cannot be ranked.
  static DriverToday compute({
    required Iterable<Booking> bookings,
    required Iterable<Vehicle> vehicles,
    required Iterable<Load> loads,
    required DriverContext? ctx,
    required DateTime now,
    ScheduleRules rules = const ScheduleRules(),
  }) {
    final mine = bookings.toList();
    return DriverToday(
      earningsToday: EarningsSummary.from(mine, now).today,
      activeTrips: mine.where((b) => b.status != BookingStatus.delivered && b.status != BookingStatus.cancelled && !b.isUpcoming(now, rules)).length,
      upcomingCount: upcomingTrips(mine, now, rules).length,
      papersExpiring: vehicles.fold(0, (n, v) => n + v.docsExpiringWithin(now, days: paperDays).length),
      recommendedLoads: ctx == null ? 0 : LoadRanker.rank(loads, ctx).length,
    );
  }
}

/// Four tiles under the online switch: today's earnings, trips, papers and
/// loads picked for the driver. Each opens the screen behind it.
class DriverTodayStrip extends StatefulWidget {
  final Stream<List<Booking>> bookings;
  final Stream<List<Vehicle>> vehicles;
  final Stream<List<Load>> loads;
  final VoidCallback onEarnings;
  final VoidCallback onTrips;
  final VoidCallback onPapers;
  final VoidCallback onLoads;

  /// Test hooks.
  final Future<DriverContext?> Function()? loadContext;
  final DateTime Function() now;

  const DriverTodayStrip({
    super.key,
    required this.bookings,
    required this.vehicles,
    required this.loads,
    required this.onEarnings,
    required this.onTrips,
    required this.onPapers,
    required this.onLoads,
    this.loadContext,
    this.now = DateTime.now,
  });

  @override
  State<DriverTodayStrip> createState() => _DriverTodayStripState();
}

class _DriverTodayStripState extends State<DriverTodayStrip> {
  DriverContext? _ctx;
  List<Booking> _bookings = const [];
  List<Vehicle> _vehicles = const [];
  List<Load> _loads = const [];
  final _subs = <dynamic>[];

  @override
  void initState() {
    super.initState();
    (widget.loadContext ?? () async => MatchService.driverContext())().then((c) {
      if (mounted) setState(() => _ctx = c);
    }).catchError((_) {});
    _subs.add(widget.bookings.listen((b) {
      if (mounted) setState(() => _bookings = b);
    }, onError: (_) {}));
    _subs.add(widget.vehicles.listen((v) {
      if (mounted) setState(() => _vehicles = v);
    }, onError: (_) {}));
    _subs.add(widget.loads.listen((l) {
      if (mounted) setState(() => _loads = l);
    }, onError: (_) {}));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Widget _tile(String id, IconData icon, String value, String label, VoidCallback onTap, {bool alert = false}) {
    return Expanded(
      child: Semantics(
        button: true,
        label: '$label: $value',
        child: InkWell(
          key: ValueKey('today_$id'),
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 88),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: alert ? AppColors.warning : AppColors.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 20, color: alert ? AppColors.warning : AppColors.primary),
              const SizedBox(height: 6),
              Text(value, key: ValueKey('todayN_$id'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: AppColors.muted)),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = DriverToday.compute(
      bookings: _bookings,
      vehicles: _vehicles,
      loads: _loads,
      ctx: _ctx,
      now: widget.now(),
      rules: PricingService.config.schedule,
    );
    return Padding(
      key: const ValueKey('driverToday'),
      padding: const EdgeInsets.only(top: 14),
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _tile('earnings', Icons.currency_rupee_rounded, formatRupees(t.earningsToday), tr(context, 'todayEarnings'), widget.onEarnings),
          const SizedBox(width: 8),
          _tile('trips', Icons.route_rounded, '${t.activeTrips + t.upcomingCount}', trf(context, 'todayTripsLabel', {'a': t.activeTrips, 'u': t.upcomingCount}), widget.onTrips),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _tile('papers', Icons.assignment_late_rounded, '${t.papersExpiring}', trf(context, 'todayPapersLabel', {'d': DriverToday.paperDays}), widget.onPapers, alert: t.papersExpiring > 0),
          const SizedBox(width: 8),
          _tile('loads', Icons.recommend_rounded, '${t.recommendedLoads}', tr(context, 'todayLoadsLabel'), widget.onLoads),
        ]),
      ]),
    );
  }
}
