import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/dispatch/bid_ranking.dart';
import '../../core/dispatch/dispatch_models.dart';
import '../../core/dispatch/load_dispatch_service.dart';
import '../../core/dispatch/trust_lookup.dart';
import '../../core/errors/error_text.dart';
import '../../core/features/features.dart';
import '../../core/l10n/l10n.dart';
import '../../core/models/load.dart';
import '../../core/models/offer.dart';
import '../../core/services/features_service.dart';
import '../../core/vehicles/vehicle_painter.dart';
import '../../core/services/load_service.dart';
import '../../core/services/offer_service.dart';
import '../../core/services/server_clock.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/trust/public_trust.dart';
import '../../core/trust/public_trust_card.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/ds/app_button.dart';
import '../../core/widgets/ds/app_dialogs.dart';
import '../../core/widgets/ds/app_top_bar.dart';
import '../../core/widgets/ds/bid_card.dart';
import '../../core/widgets/ds/countdown_ring.dart';
import '../../core/widgets/ds/route_ribbon.dart';
import '../../core/widgets/ds/sheet_kit.dart';
import '../../core/widgets/ds/status_badge.dart';
import '../booking_tracking_screen.dart';
import '../instant_wait_card.dart';
import 'auto_accept_sheet.dart';

/// U20: one screen for a posted load, whatever its mode: the route and price, the live state (the bid window, the
/// instant search, or the driver who took it) and every bid as a card. The customer sorts them, accepts one (the
/// others close) or counters once. With no bid after the window the screen says what to do next. With
/// `dispatchV2` off it shows the old open load and its offers in the same cards.
class BidRoomScreen extends StatefulWidget {
  final String loadId;
  const BidRoomScreen({super.key, required this.loadId});

  @override
  State<BidRoomScreen> createState() => _BidRoomScreenState();
}

class _BidRoomScreenState extends State<BidRoomScreen> {
  StreamSubscription<Load?>? _loadSub;
  StreamSubscription<List<Offer>>? _offerSub;
  Load? _load;
  bool _loaded = false;
  List<Offer> _offers = const [];
  final Map<String, PublicTrust?> _trust = {};
  BidSort _sort = BidSort.bestPrice;
  Timer? _tick;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadSub = LoadService.watchById(widget.loadId).listen((l) {
      if (mounted) {
        setState(() {
          _load = l;
          _loaded = true;
        });
      }
    });
    _offerSub = OfferService.watchForLoad(widget.loadId).listen((o) {
      if (!mounted) return;
      setState(() => _offers = o);
      for (final x in o) {
        if (!_trust.containsKey(x.driverId)) {
          _trust[x.driverId] = null;
          TrustLookup.of(x.driverId).then((t) {
            if (mounted) setState(() => _trust[x.driverId] = t);
          });
        }
      }
    }, onError: (_) {});
    // The window and the "no bid" advice change with time, not only with data.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _loadSub?.cancel();
    _offerSub?.cancel();
    super.dispose();
  }

  List<BidView> get _views => [
        for (final o in _offers)
          if (o.isOpen) BidView(o, rating: _trust[o.driverId]?.rating, verified: _trust[o.driverId]?.verified ?? false),
      ];

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      if (mounted) showSnack(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept(BidView v) async {
    final ok = await showConfirmDialog(
      context,
      title: tr(context, 'brAccept'),
      message: trf(context, 'brAcceptAsk', {'amount': formatPaise(v.pricePaise)}),
      confirmLabel: tr(context, 'brYes'),
    );
    if (!ok || !mounted) return;
    await _run(() => OfferService.acceptBid(v.offer, _offers));
  }

  Future<void> _counter(BidView v) async {
    final sent = await showAppSheet<int>(
      context,
      title: tr(context, 'brCounterTitle'),
      builder: (ctx) => _CounterSheet(startRupees: v.pricePaise ~/ 100),
    );
    if (sent == null || !mounted) return;
    await _run(() async {
      await OfferService.counter(v.offer.id, sent);
      if (mounted) showSnack(context, trf(context, 'brCounterSent', {'amount': formatPaise(sent)}));
    });
  }

  Future<void> _autoAccept() async {
    final load = _load;
    if (load == null) return;
    final choice = await showAppSheet<AutoAcceptChoice>(
      context,
      title: tr(context, 'brAutoTitle'),
      builder: (_) => AutoAcceptSheet(current: load.autoAccept, suggestRupees: (load.budget ?? 0).round()),
    );
    if (choice == null || !mounted) return;
    await _run(() => LoadDispatchService.setAutoAccept(load, choice.rule));
  }

  Future<void> _suggest(NoBidSuggestion s) async {
    final load = _load;
    if (load == null) return;
    switch (s) {
      case NoBidSuggestion.raisePrice:
        await _run(() async {
          final next = await LoadDispatchService.raisePrice(load, 10);
          if (mounted) showSnack(context, next == null ? tr(context, 'uxPriceLimit') : trf(context, 'uxPriceRaised', {'amount': formatPaise(next * 100)}));
        });
      case NoBidSuggestion.moreTime:
        await _run(() async {
          await LoadDispatchService.extendBidWindow(load);
        });
      case NoBidSuggestion.goInstant:
        await _run(() async {
          await LoadDispatchService.switchToInstant(load);
        });
      case NoBidSuggestion.schedule:
        if (mounted) Navigator.of(context).pop('schedule');
    }
  }

  String _suggestionLabel(NoBidSuggestion s) => tr(context, switch (s) {
        NoBidSuggestion.raisePrice => 'brRaisePrice',
        NoBidSuggestion.moreTime => 'brMoreTime',
        NoBidSuggestion.goInstant => 'brGoInstant',
        NoBidSuggestion.schedule => 'brSchedule',
      });

  Widget _stateSection(Load load) {
    final c = context.ds;
    if (load.bookingId != null && !load.isOpen) {
      return AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [Icon(Icons.check_circle_rounded, color: c.success), const SizedBox(width: DsSpace.s2), Expanded(child: Text(tr(context, 'brFound'), key: const ValueKey('brFound'), style: DsType.title.copyWith(color: c.textStrong)))]),
          const SizedBox(height: DsSpace.s3),
          AppButton(key: const ValueKey('brTrack'), label: tr(context, 'brTrack'), icon: Icons.local_shipping_rounded, onPressed: () => openBookingTracking(context, load.bookingId!)),
        ]),
      );
    }
    if (!load.isOpen) return AppCard(child: Text(tr(context, 'brClosed'), key: const ValueKey('brClosed'), style: DsType.body.copyWith(color: c.textMuted)));
    final now = ServerClock.now();
    final live = BidRanking.live(_views);
    final children = <Widget>[];
    if (load.mode == LoadMode.bid && load.bidWindowEnds != null) {
      final ends = load.bidWindowEnds!;
      if (ends.isAfter(now)) {
        children.add(AppCard(
          child: Row(children: [
            CountdownRing(key: const ValueKey('brRing'), endsAt: ends, totalSeconds: LoadDispatchService.configFor(load).bidWindowMinutes * 60, size: 72),
            const SizedBox(width: DsSpace.s4),
            Expanded(child: Text(tr(context, 'brWindowLeft'), style: DsType.subtitle.copyWith(color: c.textStrong))),
          ]),
        ));
      } else {
        children.add(Text(tr(context, 'brWindowClosed'), key: const ValueKey('brWindowClosed'), style: DsType.body.copyWith(color: c.textMuted)));
      }
    } else if (FeaturesService.isOn(FeatureKey.dispatchV2) && load.mode == LoadMode.instant && load.createdAt != null) {
      children.add(InstantWaitCard(load: load));
    } else if (_views.isEmpty) {
      children.add(Text(tr(context, 'brWaiting'), key: const ValueKey('brWaiting'), style: DsType.body.copyWith(color: c.textMuted)));
    }
    if (load.mode == LoadMode.bid) {
      final advice = BidSuggestions.whenNoBids(liveBids: live.length + _views.where((v) => v.offer.status != OfferStatus.pending).length, windowEnds: load.bidWindowEnds, now: now);
      if (advice.isNotEmpty) {
        children.add(const SizedBox(height: DsSpace.s3));
        children.add(Text(tr(context, 'brNoBidsHelp'), style: DsType.title.copyWith(color: c.textStrong)));
        for (final s in advice) {
          children.add(Padding(
            padding: const EdgeInsets.only(top: DsSpace.s2),
            child: AppButton(key: ValueKey('brSuggest_${s.name}'), label: _suggestionLabel(s), kind: s == advice.first ? AppButtonKind.primary : AppButtonKind.secondary, onPressed: _busy ? null : () => _suggest(s)),
          ));
        }
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  List<BidTag> _tagsOf(String id, Map<String, Set<BidTagKind>> tags) => [
        for (final k in tags[id] ?? const <BidTagKind>{})
          switch (k) {
            BidTagKind.bestPrice => BidTag.bestPrice,
            BidTagKind.nearest => BidTag.nearest,
            BidTagKind.topRated => BidTag.topRated,
            BidTagKind.fastest => BidTag.fastest,
          }
      ];

  Widget _bids(Load load) {
    final c = context.ds;
    final views = _views;
    final tags = BidRanking.tags(BidRanking.live(views));
    final sorted = BidRanking.sort(views.where((v) => v.offer.status == OfferStatus.pending), _sort);
    final others = views.where((v) => v.offer.status != OfferStatus.pending).toList();
    final open = load.isOpen;
    if (views.isEmpty) return Padding(padding: const EdgeInsets.symmetric(vertical: DsSpace.s4), child: Text(tr(context, 'brNoBids'), key: const ValueKey('brNoBids'), style: DsType.body.copyWith(color: c.textMuted)));
    Widget card(BidView v, {bool actions = false}) {
      final o = v.offer;
      final note = o.note == null ? null : tr(context, 'bnote_${o.note!.value}');
      return Padding(
        padding: const EdgeInsets.only(bottom: DsSpace.s3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          BidCard(
            key: ValueKey('bid_${o.id}'),
            driverName: o.driverName.isEmpty ? '-' : o.driverName,
            rating: v.rating,
            trips: _trust[o.driverId]?.trips ?? 0,
            verified: v.verified,
            pricePaise: o.pricePaise,
            etaMinutes: o.etaMinutes,
            tags: actions ? _tagsOf(o.id, tags) : const [],
            note: note,
            trust: PublicTrustCard(driverId: o.driverId),
            counterPaise: o.counterPaise,
            vehicle: FeaturesService.isOn(FeatureKey.vehicleCatalog) ? VehicleTypeArt(o.vehicleType, width: 120) : null,
            onAccept: actions && open && !_busy ? () => _accept(v) : null,
            onCounter: actions && open && o.canCounter && !_busy ? () => _counter(v) : null,
          ),
          if (o.status == OfferStatus.selected) Padding(padding: const EdgeInsets.only(top: DsSpace.s1), child: StatusBadge(label: tr(context, 'brSelectedWait'), tone: StatusTone.progress, icon: Icons.hourglass_top_rounded)),
          if (o.status == OfferStatus.countered) Padding(padding: const EdgeInsets.only(top: DsSpace.s1), child: StatusBadge(label: tr(context, 'brCountered'), tone: StatusTone.attention, icon: Icons.swap_horiz_rounded)),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (sorted.length > 1)
        QuickChipRow<BidSort>(
          padding: EdgeInsets.zero,
          options: [
            (BidSort.bestPrice, tr(context, 'uxTagBestPrice')),
            (BidSort.nearest, tr(context, 'uxTagNearest')),
            (BidSort.topRated, tr(context, 'uxTagTopRated')),
            (BidSort.fastest, tr(context, 'uxTagFastest')),
          ],
          selected: _sort,
          onChanged: (v) => setState(() => _sort = v ?? _sort),
        ),
      const SizedBox(height: DsSpace.s2),
      for (final v in sorted) card(v, actions: true),
      for (final v in others) card(v),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final load = _load;
    return Scaffold(
      appBar: AppTopBar(title: tr(context, 'brTitle')),
      body: !_loaded
          ? const Padding(padding: EdgeInsets.all(DsSpace.gutter), child: SkeletonList())
          : load == null
              ? EmptyState(icon: Icons.inventory_2_outlined, title: tr(context, 'brClosed'))
              : ListView(padding: const EdgeInsets.all(DsSpace.gutter), children: [
                  RouteRibbon(from: load.pickup, to: load.drop, distanceKm: null),
                  if (load.budget != null)
                    Padding(
                      padding: const EdgeInsets.only(top: DsSpace.s3),
                      child: Text(trf(context, 'uxPriceNow', {'amount': formatPaise((load.budget! * 100).round())}), key: const ValueKey('brPrice'), style: DsType.subtitle.copyWith(color: c.textStrong)),
                    ),
                  const SizedBox(height: DsSpace.s4),
                  _stateSection(load),
                  if (load.isOpen && FeaturesService.isOn(FeatureKey.dispatchV2))
                    Padding(
                      padding: const EdgeInsets.only(top: DsSpace.s3),
                      child: Row(children: [
                        Expanded(
                          child: load.autoAccept == null
                              ? AppButton(key: const ValueKey('brAuto'), label: tr(context, 'brAutoTitle'), kind: AppButtonKind.secondary, icon: Icons.bolt_rounded, onPressed: _autoAccept)
                              : AppButton(key: const ValueKey('brAuto'), label: trf(context, 'brAutoOn', {'amount': formatPaise(load.autoAccept!.maxPaise)}), kind: AppButtonKind.secondary, icon: Icons.bolt_rounded, onPressed: _autoAccept),
                        ),
                      ]),
                    ),
                  const SizedBox(height: DsSpace.s5),
                  Semantics(header: true, child: Text(tr(context, 'brBids'), style: DsType.title.copyWith(color: c.textStrong))),
                  const SizedBox(height: DsSpace.s2),
                  _bids(load),
                  const SizedBox(height: DsSpace.s3),
                  Text(tr(context, 'brChatAfter'), style: DsType.caption.copyWith(color: c.textMuted)),
                ]),
    );
  }
}

/// The counter price sheet. It owns its text controller, so the controller lives exactly as long as the sheet.
class _CounterSheet extends StatefulWidget {
  final int startRupees;
  const _CounterSheet({required this.startRupees});

  @override
  State<_CounterSheet> createState() => _CounterSheetState();
}

class _CounterSheetState extends State<_CounterSheet> {
  late final _price = TextEditingController(text: '${widget.startRupees}');

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(tr(context, 'brCounterHint'), style: DsType.bodySmall.copyWith(color: context.ds.textMuted)),
      const SizedBox(height: DsSpace.s3),
      TextField(key: const ValueKey('counterField'), controller: _price, keyboardType: TextInputType.number, decoration: const InputDecoration(prefixText: '₹ ')),
      const SizedBox(height: DsSpace.s3),
      AppButton(
        key: const ValueKey('counterSend'),
        label: tr(context, 'brSend'),
        onPressed: () {
          final r = int.tryParse(_price.text.trim());
          if (r != null && r > 0 && r * 100 <= OfferService.maxPaise) Navigator.of(context).pop(r * 100);
        },
      ),
    ]);
  }
}
