import 'package:flutter/material.dart';

import '../../core/adapters/connect_adapters.dart' show DemandCell;
import '../../core/constants/logistics.dart';
import '../../core/dispatch/load_radar.dart';
import '../../core/home/driver_home_logic.dart';
import '../../core/home/home_customize_sheet.dart';
import '../../core/home/home_layout.dart';
import '../../core/l10n/l10n.dart';
import '../../core/models/booking.dart';
import '../../core/models/earnings.dart';
import '../../core/models/offer.dart';
import '../../core/models/vehicle.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/ds/app_button.dart';
import '../../core/widgets/ds/route_ribbon.dart';
import '../../core/widgets/ds/skeleton.dart';
import '../../core/widgets/ds/status_badge.dart';
import '../../core/widgets/live_stream.dart' show ErrorState;
import '../v2/driver_home_v2.dart' show RadarLine, radarLine, pickVehicle;
import 'driver_home_parts.dart';

/// E22: the sections of the v3 driver home. The online hero is locked; the rest can be moved or hidden.
class DriverHomeSections {
  DriverHomeSections._();

  static const hero = 'hero', truck = 'truck', alerts = 'alerts', trip = 'trip', returns = 'returns', papers = 'papers';
  static const level = 'level', demand = 'demand', actions = 'actions', bids = 'bids', more = 'more';
  static const all = [hero, truck, alerts, trip, returns, papers, level, demand, actions, bids, more];
  static const locked = {hero};

  static const labels = {
    hero: 'dhOnlineOn',
    truck: 'dhTruckToday',
    alerts: 'd3Alerts',
    trip: 'activeTrip',
    returns: 'd3Returns',
    papers: 'd3Papers',
    level: 'd3LevelTitle',
    demand: 'd3Demand',
    actions: 'd3Actions',
    bids: 'd3Bids',
    more: 'dhMore',
  };

  static HomeLayout get defaults => HomeLayout.parse(null, all, locked: locked);
}

/// E22 (flag driverHomeV3): the driver home built from sections. Same inputs as the v2 home plus a few actions;
/// the host owns the data. Extra reads: the 3 newest bids (one small listener) and, while a trip runs, the open
/// loads listener the return-load suggestions already use. Level, streak, papers and the goal cost nothing.
class DriverHomeV3 extends StatefulWidget {
  final bool online;
  final ValueChanged<bool> onOnline;
  final Stream<List<Vehicle>> vehicles;

  /// All of the driver's bookings (today's earnings, level, streak, the trip in progress).
  final Stream<List<Booking>> bookings;
  final String? vehicleId;
  final ValueChanged<String> onVehicle;
  final Stream<RadarState>? radar;
  final VoidCallback onAddVehicle;
  final VoidCallback onOpenLoads;
  final VoidCallback onOpenBids;
  final VoidCallback onOpenEarnings;
  final VoidCallback onOpenVehicles;
  final Widget header;
  final List<Widget> banners;
  final List<Widget> trips;
  final List<Widget> more;

  /// The return-load suggestions for the trip in progress.
  final Widget Function(Booking trip)? returnLoads;
  final Stream<List<Offer>> Function()? recentBids;
  final Future<List<DemandCell>> Function()? demand;
  final Future<HomeLayout> Function()? loadLayout;
  final Future<void> Function(HomeLayout layout)? saveLayout;
  final Future<int?> Function()? loadGoal;
  final Future<void> Function(int? goal)? saveGoal;
  final DateTime Function() now;

  const DriverHomeV3({
    super.key,
    required this.online,
    required this.onOnline,
    required this.vehicles,
    required this.bookings,
    required this.vehicleId,
    required this.onVehicle,
    required this.onAddVehicle,
    required this.onOpenLoads,
    required this.onOpenBids,
    required this.onOpenEarnings,
    required this.onOpenVehicles,
    required this.header,
    this.radar,
    this.banners = const [],
    this.trips = const [],
    this.more = const [],
    this.returnLoads,
    this.recentBids,
    this.demand,
    this.loadLayout,
    this.saveLayout,
    this.loadGoal,
    this.saveGoal,
    this.now = DateTime.now,
  });

  @override
  State<DriverHomeV3> createState() => _DriverHomeV3State();
}

class _DriverHomeV3State extends State<DriverHomeV3> {
  static const _role = 'driver';
  HomeLayout? _layout;
  int? _goal;
  late Stream<List<Vehicle>> _vehicles = widget.vehicles;
  late Stream<List<Booking>> _bookings = widget.bookings;
  Stream<List<Offer>>? _bids;
  Future<List<DemandCell>>? _demand;

  @override
  void initState() {
    super.initState();
    (widget.loadLayout ?? () => HomeLayoutStore.load(_role, DriverHomeSections.all, locked: DriverHomeSections.locked))()
        .then((l) => l, onError: (_) => DriverHomeSections.defaults)
        .then((l) {
      if (mounted) setState(() => _layout = l);
    });
    (widget.loadGoal ?? DailyGoalStore.load)().then((g) => g, onError: (_) => null).then((g) {
      if (mounted) setState(() => _goal = g);
    });
  }

  @override
  void didUpdateWidget(DriverHomeV3 old) {
    super.didUpdateWidget(old);
    if (old.vehicles != widget.vehicles) _vehicles = widget.vehicles;
    if (old.bookings != widget.bookings) _bookings = widget.bookings;
  }

  Future<void> _arrange() async {
    final next = await showHomeCustomizeSheet(context, layout: _layout ?? DriverHomeSections.defaults, defaults: DriverHomeSections.defaults, labels: DriverHomeSections.labels);
    if (next == null || !mounted) return;
    setState(() => _layout = next);
    await (widget.saveLayout ?? (l) => HomeLayoutStore.save(_role, l))(next);
  }

  Future<void> _setGoal() async {
    final v = await askDailyGoal(context, _goal);
    if (v == null || !mounted) return;
    final goal = v == 0 ? null : v;
    setState(() => _goal = goal);
    await (widget.saveGoal ?? DailyGoalStore.save)(goal);
  }

  void _retry() => setState(() {
        _vehicles = widget.vehicles;
        _bookings = widget.bookings;
      });

  @override
  Widget build(BuildContext context) {
    final layout = _layout;
    return SafeArea(
      child: StreamBuilder<List<Vehicle>>(
        stream: _vehicles,
        builder: (context, vs) => StreamBuilder<List<Booking>>(
          stream: _bookings,
          builder: (context, bs) {
            final failed = vs.hasError || bs.hasError;
            final ready = layout != null && (failed || (vs.hasData && bs.hasData));
            final d = _DriverData(vs.data ?? const [], bs.data ?? const [], widget.now());
            return ListView(padding: const EdgeInsets.all(DsSpace.gutter), children: [
              Row(children: [
                Expanded(child: widget.header),
                IconButton(key: const ValueKey('d3Arrange'), tooltip: tr(context, 'hlCustomize'), onPressed: layout == null ? null : _arrange, icon: const Icon(Icons.tune_rounded)),
              ]),
              const SizedBox(height: DsSpace.s4),
              if (!ready)
                const SkeletonList(key: ValueKey('d3Skeleton'), count: 4, padding: EdgeInsets.zero)
              else ...[
                if (failed) Padding(padding: const EdgeInsets.only(bottom: DsSpace.s3), child: ErrorState(compact: true, error: vs.error ?? bs.error, onRetry: _retry)),
                for (final id in layout.visible) ..._section(context, id, d),
              ],
            ]);
          },
        ),
      ),
    );
  }

  List<Widget> _section(BuildContext context, String id, _DriverData d) {
    final Widget? w = switch (id) {
      DriverHomeSections.hero => _hero(context, d),
      DriverHomeSections.truck => _truck(context, d),
      DriverHomeSections.alerts => widget.banners.isEmpty ? null : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: widget.banners),
      DriverHomeSections.trip => widget.trips.isEmpty ? null : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: widget.trips),
      DriverHomeSections.returns => d.activeTrip == null || widget.returnLoads == null ? null : widget.returnLoads!(d.activeTrip!),
      DriverHomeSections.papers => d.vehicles.isEmpty ? null : PaperHealthCard(health: PaperHealth.of(d.vehicles, d.now), onOpen: widget.onOpenVehicles),
      DriverHomeSections.level => LevelStreakCard(delivered: d.earnings.completedTrips, streak: deliveryStreak(d.bookings, d.now)),
      DriverHomeSections.demand => widget.online && widget.demand != null ? _demandStrip() : null,
      DriverHomeSections.actions => QuickActions(actions: [
          ('d3QLoads', Icons.inventory_2_outlined, tr(context, 'availableLoads'), widget.onOpenLoads),
          ('d3QBids', Icons.gavel_rounded, tr(context, 'd3Bids'), widget.onOpenBids),
          ('d3QEarnings', Icons.account_balance_wallet_outlined, tr(context, 'todayEarnings'), widget.onOpenEarnings),
          ('d3QVehicles', Icons.local_shipping_outlined, tr(context, 'd3Papers'), widget.onOpenVehicles),
        ]),
      DriverHomeSections.bids => widget.recentBids == null ? null : _bidsCard(context),
      DriverHomeSections.more => widget.more.isEmpty ? null : _more(context),
      _ => null,
    };
    if (w == null) return const [];
    return [w, const SizedBox(height: DsSpace.s4)];
  }

  Widget _hero(BuildContext context, _DriverData d) {
    final c = context.ds;
    final online = widget.online;
    final on = online ? DsHero.on : c.onPrimary;
    return Container(
      key: const ValueKey('d3Hero'),
      padding: const EdgeInsets.all(DsSpace.s5),
      decoration: BoxDecoration(
        gradient: online ? const LinearGradient(colors: DsHero.colors, begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
        color: online ? null : c.textMuted,
        borderRadius: DsRadius.all(DsRadius.xl),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(tr(context, online ? 'dhOnlineOn' : 'dhOnlineOff'), style: DsType.headline.copyWith(color: on))),
          // A big target for a thumb: the switch is scaled up.
          Transform.scale(scale: 1.35, child: Switch(key: const ValueKey('onlineSwitch'), value: online, onChanged: widget.onOnline)),
        ]),
        const SizedBox(height: DsSpace.s3),
        StreamBuilder<RadarState>(
          stream: widget.radar,
          builder: (context, snap) {
            final waiting = snap.data == null ? 0 : (snap.data!.current == null ? 0 : 1 + snap.data!.waiting);
            final line = radarLine(online: online, vehicleCount: d.vehicles.length, waiting: waiting);
            final text = switch (line) {
              RadarLine.offline => tr(context, 'dhRadarOff'),
              RadarLine.noTruck => tr(context, 'dhRadarNoTruck'),
              RadarLine.searching => tr(context, 'dhRadarOn'),
              RadarLine.waiting => trf(context, 'dhRadarWait', {'n': waiting}),
            };
            return Semantics(
              container: true,
              liveRegion: true,
              child: Row(key: const ValueKey('d3Radar'), children: [
                RadarPulse(active: line == RadarLine.searching || line == RadarLine.waiting, color: on, size: 40),
                const SizedBox(width: DsSpace.s2),
                Expanded(child: Text(text, style: DsType.bodySmall.copyWith(color: on))),
              ]),
            );
          },
        ),
        const SizedBox(height: DsSpace.s4),
        Wrap(spacing: DsSpace.s4, runSpacing: DsSpace.s2, crossAxisAlignment: WrapCrossAlignment.center, children: [
          EarningsRing(todayRupees: d.earnings.today, goalRupees: _goal, onSetGoal: _setGoal, color: on, track: on.withValues(alpha: 0.25)),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(tr(context, 'todayEarnings'), style: DsType.bodySmall.copyWith(color: on.withValues(alpha: 0.85))),
              TextButton(
                key: const ValueKey('d3OpenEarnings'),
                style: TextButton.styleFrom(foregroundColor: on, padding: EdgeInsets.zero),
                onPressed: widget.onOpenEarnings,
                child: Text(tr(context, 'd3SeeEarnings')),
              ),
            ]),
          ),
        ]),
      ]),
    );
  }

  Widget _truck(BuildContext context, _DriverData d) {
    final c = context.ds;
    if (d.vehicles.isEmpty) {
      return AppCard(
        key: const ValueKey('d3NoTruck'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.local_shipping_rounded, color: c.warning),
            const SizedBox(width: DsSpace.s3),
            Expanded(child: Text(tr(context, 'noVehicleTitle'), style: DsType.subtitle.copyWith(color: c.textStrong))),
          ]),
          const SizedBox(height: DsSpace.s3),
          AppButton(key: const ValueKey('d3AddTruck'), label: tr(context, 'addVehicle'), kind: AppButtonKind.secondary, onPressed: widget.onAddVehicle),
        ]),
      );
    }
    final chosen = pickVehicle(d.vehicles, widget.vehicleId)!;
    return Column(key: const ValueKey('d3Truck'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr(context, 'dhTruckToday'), style: DsType.label.copyWith(color: c.textMuted)),
      const SizedBox(height: DsSpace.s2),
      Wrap(spacing: DsSpace.s2, runSpacing: DsSpace.s2, children: [
        for (final v in d.vehicles)
          ChoiceChip(
            key: ValueKey('d3Vehicle_${v.id}'),
            avatar: const Icon(Icons.local_shipping_outlined, size: 18),
            label: Text('${v.number} · ${v.type}'),
            selected: v.id == chosen.id,
            onSelected: (_) => widget.onVehicle(v.id),
          ),
      ]),
    ]);
  }

  Widget _demandStrip() {
    _demand ??= widget.demand!().then((l) => l, onError: (_) => <DemandCell>[]);
    return FutureBuilder<List<DemandCell>>(future: _demand, builder: (context, snap) => DemandStrip(cells: snap.data ?? const []));
  }

  Widget _bidsCard(BuildContext context) {
    final c = context.ds;
    _bids ??= widget.recentBids!();
    return StreamBuilder<List<Offer>>(
      stream: _bids,
      builder: (context, snap) {
        final list = snap.data ?? const <Offer>[];
        if (snap.hasError || (snap.hasData && list.isEmpty)) return const SizedBox.shrink();
        return Column(key: const ValueKey('d3Bids'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Semantics(header: true, child: Text(tr(context, 'd3Bids'), style: DsType.subtitle.copyWith(color: c.textStrong))),
            TextButton(key: const ValueKey('d3AllBids'), onPressed: widget.onOpenBids, child: Text(tr(context, 'h3SeeAll'))),
          ]),
          const SizedBox(height: DsSpace.s2),
          if (!snap.hasData) const Center(child: CircularProgressIndicator()),
          for (final o in list.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: DsSpace.s2),
              child: AppCard(
                key: ValueKey('d3Bid_${o.id}'),
                onTap: widget.onOpenBids,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Wrap(spacing: DsSpace.s2, runSpacing: DsSpace.s1, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(formatPaise(o.pricePaise), style: DsType.subtitle.copyWith(color: c.textStrong)),
                    StatusBadge(label: tr(context, 'd3Bid_${_bidState(o)}'), tone: _bidTone(o)),
                  ]),
                  const SizedBox(height: DsSpace.s2),
                  RouteRibbon(from: o.pickup, to: o.drop),
                ]),
              ),
            ),
        ]);
      },
    );
  }

  static String _bidState(Offer o) => switch (o.status) {
        OfferStatus.confirmed => 'won',
        OfferStatus.rejected || OfferStatus.withdrawn => 'closed',
        OfferStatus.countered => 'counter',
        _ => 'waiting',
      };

  static StatusTone _bidTone(Offer o) => switch (o.status) {
        OfferStatus.confirmed => StatusTone.success,
        OfferStatus.rejected || OfferStatus.withdrawn => StatusTone.neutral,
        _ => StatusTone.progress,
      };

  Widget _more(BuildContext context) {
    final c = context.ds;
    return Column(key: const ValueKey('d3More'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(header: true, child: Text(tr(context, 'dhMore'), style: DsType.title.copyWith(color: c.textStrong))),
      const SizedBox(height: DsSpace.s2),
      ...widget.more,
    ]);
  }
}

class _DriverData {
  final List<Vehicle> vehicles;
  final List<Booking> bookings;
  final DateTime now;
  _DriverData(this.vehicles, this.bookings, this.now);

  late final EarningsSummary earnings = EarningsSummary.from(bookings, now);
  /// A trip with the goods on board: where return loads from its drop make sense.
  late final Booking? activeTrip = bookings.where((b) => const [BookingStatus.pickedUp, BookingStatus.inTransit, BookingStatus.unloading].contains(b.status)).firstOrNull;
}
