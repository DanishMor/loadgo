import 'package:flutter/material.dart';

import '../../core/announcement/announcement.dart';
import '../../core/assistant/sahayak_screen.dart';
import '../../core/bilty/lr_model.dart';
import '../../core/constants/logistics.dart';
import '../../core/bilty/lr_service.dart';
import '../../core/features/features.dart';
import '../../core/home/home_customize_sheet.dart';
import '../../core/home/home_layout.dart';
import '../../core/l10n/l10n.dart';
import '../../core/l10n/language_widgets.dart';
import '../../core/models/booking.dart';
import '../../core/models/load.dart';
import '../../core/notifications/notifications_screen.dart';
import '../../core/pilot/payment_nudge_card.dart';
import '../../core/services/auth_helpers.dart' show maskPhone;
import '../../core/services/backend.dart';
import '../../core/services/booking_service.dart';
import '../../core/services/features_service.dart';
import '../../core/services/load_service.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/vehicles/vehicle_catalog.dart';
import '../../core/vehicles/vehicle_painter.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/ds/app_button.dart';
import '../../core/widgets/ds/route_ribbon.dart';
import '../../core/widgets/ds/skeleton.dart';
import '../../core/widgets/ds/status_badge.dart';
import '../../core/widgets/live_stream.dart' show ErrorState;
import '../../core/widgets/logistics_labels.dart';
import '../../core/widgets/offers_gate.dart';
import '../../core/widgets/role_tour_card.dart';
import '../v2/booking_wizard_model.dart';
import '../v2/customer_home_v2.dart' show RecentRoute;

/// E21: the sections of the v3 customer home, in their default order. The hero is locked (always shown); recent LRs
/// start hidden (most customers never issue one).
class CustomerHomeSections {
  CustomerHomeSections._();

  static const hero = 'hero', trip = 'trip', vehicles = 'vehicles', routes = 'routes', offers = 'offers';
  static const promise = 'promise', sahayak = 'sahayak', lrs = 'lrs', referral = 'referral', more = 'more';
  static const all = [hero, trip, vehicles, routes, offers, promise, sahayak, lrs, referral, more];
  static const locked = {hero};
  static const hiddenByDefault = {lrs};

  /// Words key of each section in the arrange sheet.
  static const labels = {
    hero: 'hvBookBig',
    trip: 'hvTrip',
    vehicles: 'h3Vehicles',
    routes: 'h3Routes',
    offers: 'offersAndCredits',
    promise: 'h3Promise',
    sahayak: 'h3Ask',
    lrs: 'h3Lrs',
    referral: 'h3Refer',
    more: 'hvMore',
  };

  static HomeLayout get defaults => HomeLayout.parse(null, all, locked: locked, hiddenByDefault: hiddenByDefault);
}

/// E21 (flag homeV3): the customer home built from sections the person can reorder and hide (kept on the phone).
/// Same actions as [CustomerHomeV2], so the shell can switch between them. Reads: the bookings and loads listeners
/// the v2 home already has, plus one read of at most 3 LRs when that section is shown.
class CustomerHomeV3 extends StatefulWidget {
  final VoidCallback onBook;
  final void Function(WizardDraft draft) onBookFrom;
  final ValueChanged<String> onOpenBooking;
  final ValueChanged<String> onOpenLoad;
  final VoidCallback onOpenTrips;
  final VoidCallback? onOpenOffers;
  final VoidCallback? onOpenCatalog;
  final VoidCallback? onOpenTemplates;
  final List<Widget> more;
  final SahayakActions? sahayak;

  /// Tests give the data instead of the live sources.
  final Stream<List<Booking>> Function()? bookings;
  final Stream<List<Load>> Function()? loads;
  final Future<List<LrPublic>> Function()? lrs;
  final Future<List<VehicleSpec>> Function()? catalog;
  final Future<HomeLayout> Function()? loadLayout;
  final Future<void> Function(HomeLayout layout)? saveLayout;

  const CustomerHomeV3({
    super.key,
    required this.onBook,
    required this.onBookFrom,
    required this.onOpenBooking,
    required this.onOpenLoad,
    required this.onOpenTrips,
    this.onOpenOffers,
    this.onOpenCatalog,
    this.onOpenTemplates,
    this.more = const [],
    this.sahayak,
    this.bookings,
    this.loads,
    this.lrs,
    this.catalog,
    this.loadLayout,
    this.saveLayout,
  });

  @override
  State<CustomerHomeV3> createState() => _CustomerHomeV3State();
}

class _CustomerHomeV3State extends State<CustomerHomeV3> {
  static const _role = 'customer';
  HomeLayout? _layout;
  late Stream<List<Booking>> _bookings = _openBookings();
  late Stream<List<Load>> _loads = _openLoads();
  Future<List<LrPublic>>? _lrs;
  Future<List<VehicleSpec>>? _catalog;

  Stream<List<Booking>> _openBookings() => (widget.bookings ?? () => BookingService.watchForCustomer())();
  Stream<List<Load>> _openLoads() => (widget.loads ?? LoadService.watchMine)();

  @override
  void initState() {
    super.initState();
    (widget.loadLayout ?? () => HomeLayoutStore.load(_role, CustomerHomeSections.all, locked: CustomerHomeSections.locked, hiddenByDefault: CustomerHomeSections.hiddenByDefault))()
        .then((l) => l, onError: (_) => CustomerHomeSections.defaults)
        .then((l) {
      if (mounted) setState(() => _layout = l);
    });
  }

  Future<void> _arrange() async {
    final current = _layout ?? CustomerHomeSections.defaults;
    final next = await showHomeCustomizeSheet(context, layout: current, defaults: CustomerHomeSections.defaults, labels: CustomerHomeSections.labels);
    if (next == null || !mounted) return;
    setState(() => _layout = next);
    await (widget.saveLayout ?? (l) => HomeLayoutStore.save(_role, l))(next);
  }

  void _retry() => setState(() {
        _bookings = _openBookings();
        _loads = _openLoads();
      });

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final phone = Backend.currentUser?.phoneNumber ?? '';
    final who = phone.isNotEmpty ? maskPhone(phone) : tr(context, 'customer');
    final layout = _layout;
    return SafeArea(
      child: StreamBuilder<List<Booking>>(
        stream: _bookings,
        builder: (context, bookings) => StreamBuilder<List<Load>>(
          stream: _loads,
          builder: (context, loads) {
            final failed = bookings.hasError || loads.hasError;
            final ready = layout != null && (failed || (bookings.hasData && loads.hasData));
            final data = _HomeData(bookings.data ?? const [], loads.data ?? const []);
            return ListView(padding: const EdgeInsets.all(DsSpace.gutter), children: [
              Row(children: [
                CircleAvatar(radius: 24, backgroundColor: c.tint, child: Icon(Icons.person_rounded, color: c.primary)),
                const SizedBox(width: DsSpace.s3),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr(context, 'welcomeBack'), style: DsType.bodySmall.copyWith(color: c.textMuted)),
                    Text(who, maxLines: 1, overflow: TextOverflow.ellipsis, style: DsType.title.copyWith(color: c.textStrong)),
                  ]),
                ),
                IconButton(key: const ValueKey('h3Arrange'), tooltip: tr(context, 'hlCustomize'), onPressed: layout == null ? null : _arrange, icon: const Icon(Icons.tune_rounded)),
                IconButton(tooltip: tr(context, 'language'), onPressed: () => showLanguageSelector(context), icon: const Icon(Icons.language_rounded)),
                NotificationBell(onOpenBooking: widget.onOpenBooking),
              ]),
              const SizedBox(height: DsSpace.s4),
              const AnnouncementBanner(role: 'customer'),
              const PaymentNudgeCard(target: 'customer'),
              const RoleTourCard(role: RoleTour.customer),
              if (!ready)
                const SkeletonList(key: ValueKey('h3Skeleton'), count: 4, padding: EdgeInsets.zero)
              else ...[
                if (failed) Padding(padding: const EdgeInsets.only(bottom: DsSpace.s3), child: ErrorState(compact: true, error: bookings.error ?? loads.error, onRetry: _retry)),
                for (final id in layout.visible) ..._section(context, id, data),
              ],
            ]);
          },
        ),
      ),
    );
  }

  /// The widgets of one section (empty when it has nothing to show), each followed by its gap.
  List<Widget> _section(BuildContext context, String id, _HomeData d) {
    final w = switch (id) {
      CustomerHomeSections.hero => _hero(context, d),
      CustomerHomeSections.trip => _trip(context, d),
      CustomerHomeSections.vehicles => FeaturesService.isOn(FeatureKey.vehicleCatalog) ? _vehicles(context) : null,
      CustomerHomeSections.routes => d.routes.isEmpty && widget.onOpenTemplates == null ? null : _routes(context, d),
      CustomerHomeSections.offers => widget.onOpenOffers == null
          ? null
          : OffersGate(test: (s) => s.any, child: _tile(context, 'h3Offers', Icons.local_offer_outlined, tr(context, 'offersAndCredits'), null, widget.onOpenOffers!)),
      CustomerHomeSections.promise => _promise(context),
      CustomerHomeSections.sahayak => widget.sahayak == null
          ? null
          : _tile(context, 'h3Sahayak', Icons.support_agent_rounded, tr(context, 'h3Ask'), tr(context, 'h3AskSub'),
              () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SahayakScreen(role: 'customer', actions: widget.sahayak!)))),
      CustomerHomeSections.lrs => d.firstRun ? null : _recentLrs(context),
      CustomerHomeSections.referral => widget.onOpenOffers == null
          ? null
          : OffersGate(test: (s) => s.referral, child: _tile(context, 'h3Referral', Icons.card_giftcard_rounded, tr(context, 'h3Refer'), tr(context, 'referralExplain'), widget.onOpenOffers!)),
      CustomerHomeSections.more => widget.more.isEmpty ? null : _more(context),
      _ => null,
    };
    if (w == null) return const [];
    return [w, const SizedBox(height: DsSpace.s4)];
  }

  Widget _hero(BuildContext context, _HomeData d) {
    final bidOn = FeaturesService.isOn(FeatureKey.dispatchV2);
    Widget mode(IconData icon, String title, String hint) => Padding(
          padding: const EdgeInsets.symmetric(vertical: DsSpace.s1),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 20, color: DsHero.on),
            const SizedBox(width: DsSpace.s3),
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '$title  ', style: DsType.label.copyWith(color: DsHero.on)),
                TextSpan(text: hint, style: DsType.bodySmall.copyWith(color: DsHero.on.withValues(alpha: 0.85))),
              ])),
            ),
          ]),
        );
    return Container(
      key: const ValueKey('h3Hero'),
      padding: const EdgeInsets.all(DsSpace.s5),
      decoration: BoxDecoration(gradient: const LinearGradient(colors: DsHero.colors, begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: DsRadius.all(DsRadius.xl)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr(context, 'hvBookBig'), style: DsType.headline.copyWith(color: DsHero.on)),
        const SizedBox(height: DsSpace.s1),
        Text(tr(context, d.firstRun ? 'h3First' : 'hvHeroSub'), key: ValueKey(d.firstRun ? 'h3FirstRun' : 'h3HeroSub'), style: DsType.bodySmall.copyWith(color: DsHero.on.withValues(alpha: 0.85))),
        const SizedBox(height: DsSpace.s4),
        mode(Icons.bolt_rounded, tr(context, 'wzModeInstant'), tr(context, 'wzModeInstantHint')),
        if (bidOn) mode(Icons.gavel_rounded, tr(context, 'wzModeBid'), tr(context, 'wzModeBidHint')),
        mode(Icons.event_rounded, tr(context, 'wzModeSchedule'), tr(context, 'wzModeScheduleHint')),
        const SizedBox(height: DsSpace.s4),
        AppButton(key: const ValueKey('h3Book'), label: tr(context, 'hvBookBig'), big: true, icon: Icons.local_shipping_rounded, onPressed: widget.onBook),
      ]),
    );
  }

  Widget? _trip(BuildContext context, _HomeData d) {
    final c = context.ds;
    final b = d.activeTrip;
    if (b != null) {
      return AppCard(
        key: const ValueKey('h3Trip'),
        onTap: () => widget.onOpenBooking(b.id),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: DsSpace.s2, runSpacing: DsSpace.s1, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(tr(context, 'hvTrip'), style: DsType.title.copyWith(color: c.textStrong)),
            StatusBadge(label: bookingStatusLabel(context, b.status), tone: StatusTone.progress),
          ]),
          const SizedBox(height: DsSpace.s3),
          RouteRibbon(from: b.pickup, to: b.drop),
          const SizedBox(height: DsSpace.s3),
          AppButton(key: const ValueKey('h3OpenTrip'), label: tr(context, 'hvOpen'), kind: AppButtonKind.secondary, onPressed: () => widget.onOpenBooking(b.id)),
        ]),
      );
    }
    if (d.waiting.isEmpty) return null;
    return AppCard(
      key: const ValueKey('h3Waiting'),
      onTap: () => widget.onOpenLoad(d.waiting.first.id),
      child: Row(children: [
        Icon(Icons.hourglass_top_rounded, color: c.warning),
        const SizedBox(width: DsSpace.s3),
        Expanded(child: Text(trf(context, 'hvWaitingLoads', {'n': d.waiting.length}), style: DsType.subtitle.copyWith(color: c.textStrong))),
        TextButton(onPressed: () => widget.onOpenLoad(d.waiting.first.id), child: Text(tr(context, 'hvOpen'))),
      ]),
    );
  }

  Widget _vehicles(BuildContext context) {
    final c = context.ds;
    _catalog ??= (widget.catalog ?? () => VehicleCatalog.load())().then((l) => l, onError: (_) => <VehicleSpec>[]);
    return FutureBuilder<List<VehicleSpec>>(
      future: _catalog,
      builder: (context, snap) {
        final specs = [for (final s in snap.data ?? const <VehicleSpec>[]) if (s.legacyId != null) s];
        if (snap.connectionState == ConnectionState.done && specs.isEmpty) return const SizedBox.shrink();
        return Column(key: const ValueKey('h3Vehicles'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Semantics(header: true, child: Text(tr(context, 'h3Vehicles'), style: DsType.subtitle.copyWith(color: c.textStrong)))),
            if (widget.onOpenCatalog != null) TextButton(key: const ValueKey('h3SeeAll'), onPressed: widget.onOpenCatalog, child: Text(tr(context, 'h3SeeAll'))),
          ]),
          const SizedBox(height: DsSpace.s2),
          SizedBox(
            height: 132,
            child: specs.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: specs.length > 12 ? 12 : specs.length,
                    separatorBuilder: (_, _) => const SizedBox(width: DsSpace.s2),
                    itemBuilder: (context, i) {
                      final s = specs[i];
                      return SizedBox(
                        width: 128,
                        child: AppCard(
                          key: ValueKey('h3Vehicle_${s.id}'),
                          padding: const EdgeInsets.all(DsSpace.s2),
                          onTap: () => widget.onBookFrom(WizardDraft(vehicleType: s.legacyId)),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            VehicleArt(s, width: 104),
                            const SizedBox(height: DsSpace.s1),
                            ExcludeSemantics(child: Text(tr(context, s.nameKey), maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: DsType.caption.copyWith(color: c.text))),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ]);
      },
    );
  }

  Widget _routes(BuildContext context, _HomeData d) {
    final c = context.ds;
    return Column(key: const ValueKey('h3Routes'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(header: true, child: Text(tr(context, 'h3Routes'), style: DsType.subtitle.copyWith(color: c.textStrong))),
      const SizedBox(height: DsSpace.s2),
      Wrap(spacing: DsSpace.s2, runSpacing: DsSpace.s2, children: [
        for (final r in d.routes)
          ActionChip(
            key: ValueKey('h3Route_${r.pickup}_${r.drop}'),
            avatar: const Icon(Icons.history_rounded, size: 18),
            label: Text('${r.pickup} → ${r.drop}'),
            onPressed: () => widget.onBookFrom(WizardDraft(pickup: r.pickup, drop: r.drop, step: 1)),
          ),
        if (widget.onOpenTemplates != null)
          ActionChip(key: const ValueKey('h3Templates'), avatar: const Icon(Icons.bookmarks_outlined, size: 18), label: Text(tr(context, 'templatesTitle')), onPressed: widget.onOpenTemplates),
      ]),
    ]);
  }

  Widget _promise(BuildContext context) {
    final c = context.ds;
    Widget line(IconData icon, String key) => Padding(
          padding: const EdgeInsets.symmetric(vertical: DsSpace.s1),
          child: Row(children: [
            Icon(icon, size: 20, color: c.success),
            const SizedBox(width: DsSpace.s3),
            Expanded(child: Text(tr(context, key), style: DsType.bodySmall.copyWith(color: c.text))),
          ]),
        );
    return Container(
      key: const ValueKey('h3Promise'),
      padding: const EdgeInsets.all(DsSpace.s4),
      decoration: BoxDecoration(color: c.successBg, borderRadius: DsRadius.all(DsRadius.lg)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(header: true, child: Text(tr(context, 'h3Promise'), style: DsType.subtitle.copyWith(color: c.textStrong))),
        const SizedBox(height: DsSpace.s2),
        line(Icons.verified_rounded, 'hvTrust1'),
        line(Icons.password_rounded, 'hvTrust2'),
        line(Icons.phone_disabled_rounded, 'hvTrust3'),
      ]),
    );
  }

  Widget _recentLrs(BuildContext context) {
    final c = context.ds;
    _lrs ??= (widget.lrs ?? () => LrService.recentMine())().then((l) => l, onError: (_) => <LrPublic>[]);
    return FutureBuilder<List<LrPublic>>(
      future: _lrs,
      builder: (context, snap) {
        final list = snap.data ?? const <LrPublic>[];
        if (snap.connectionState == ConnectionState.done && list.isEmpty) return const SizedBox.shrink();
        return Column(key: const ValueKey('h3Lrs'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(header: true, child: Text(tr(context, 'h3Lrs'), style: DsType.subtitle.copyWith(color: c.textStrong))),
          const SizedBox(height: DsSpace.s2),
          if (list.isEmpty) const Center(child: CircularProgressIndicator()),
          for (final lr in list)
            Padding(
              padding: const EdgeInsets.only(bottom: DsSpace.s2),
              child: AppCard(
                key: ValueKey('h3Lr_${lr.id}'),
                onTap: lr.bookingId.isEmpty ? null : () => widget.onOpenBooking(lr.bookingId),
                child: Row(children: [
                  Icon(Icons.receipt_long_outlined, color: c.primary),
                  const SizedBox(width: DsSpace.s3),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(lr.lrNo, style: DsType.subtitle.copyWith(color: c.textStrong)),
                      if (lr.route.isNotEmpty) Text(lr.route, maxLines: 1, overflow: TextOverflow.ellipsis, style: DsType.bodySmall.copyWith(color: c.textMuted)),
                    ]),
                  ),
                ]),
              ),
            ),
        ]);
      },
    );
  }

  Widget _more(BuildContext context) {
    final c = context.ds;
    return Column(key: const ValueKey('h3More'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(header: true, child: Text(tr(context, 'hvMore'), style: DsType.title.copyWith(color: c.textStrong))),
      const SizedBox(height: DsSpace.s2),
      ...widget.more,
      Align(alignment: AlignmentDirectional.centerStart, child: TextButton(key: const ValueKey('h3AllTrips'), onPressed: widget.onOpenTrips, child: Text(tr(context, 'hvTabTrips')))),
    ]);
  }

  Widget _tile(BuildContext context, String key, IconData icon, String title, String? sub, VoidCallback onTap) {
    final c = context.ds;
    return AppCard(
      key: ValueKey(key),
      onTap: onTap,
      child: Row(children: [
        Icon(icon, color: c.primary),
        const SizedBox(width: DsSpace.s3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: DsType.subtitle.copyWith(color: c.textStrong)),
            if (sub != null) Text(sub, style: DsType.bodySmall.copyWith(color: c.textMuted)),
          ]),
        ),
        const Icon(Icons.chevron_right_rounded),
      ]),
    );
  }
}

/// What the sections need from the two listeners.
class _HomeData {
  final List<Booking> bookings;
  final List<Load> loads;
  _HomeData(this.bookings, this.loads);

  late final Booking? activeTrip = bookings.where((b) => b.status != BookingStatus.delivered && b.status != BookingStatus.cancelled).firstOrNull;
  late final List<Load> waiting = [for (final l in loads) if (l.isOpen) l];
  late final List<RecentRoute> routes = RecentRoute.from(loads);

  /// Nothing booked or posted yet: the hero says how a first booking works and the history sections stay away.
  bool get firstRun => bookings.isEmpty && loads.isEmpty;
}
