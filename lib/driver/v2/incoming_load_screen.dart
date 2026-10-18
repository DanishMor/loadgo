import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/dispatch/load_radar.dart';
import '../../core/errors/error_text.dart';
import '../../core/l10n/l10n.dart';
import '../../core/matching/load_ranker.dart';
import '../../core/models/load.dart';
import '../../core/models/risk.dart';
import '../../core/models/vehicle.dart';
import '../../core/services/booking_service.dart';
import '../../core/services/vehicle_service.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/ds/app_button.dart';
import '../../core/widgets/ds/countdown_ring.dart';
import '../../core/widgets/ds/feedback_kit.dart';
import '../../core/widgets/ds/route_ribbon.dart';
import '../../core/widgets/ds/app_dialogs.dart';
import '../../core/widgets/ds/slide_to_confirm.dart';
import '../../core/widgets/logistics_labels.dart';
import '../../core/dispatch/driver_bid_sheet.dart';

/// Why a card closed by itself.
enum CardGone { taken, timeUp }

/// The price the card offers, in paise: the customer's price, else the fare estimate; null when the load has neither.
int? cardFarePaise(Load load) {
  final budget = load.budget == null ? 0 : (load.budget! * 100).round();
  if (budget > 0) return budget;
  final est = load.estimate?.total;
  return est != null && est > 0 ? est : null;
}

/// The truck for a load: the one the driver chose for today when it fits, else the first free one that fits.
Vehicle? truckForLoad(List<Vehicle> all, Load load, {String? preferredId, required DateTime now}) {
  final fit = [for (final v in all) if (LoadRanker.vehicleFits(v, vehicleType: load.vehicleType, weight: load.weight, now: now)) v];
  for (final v in fit) {
    if (v.id == preferredId) return v;
  }
  return fit.isEmpty ? null : fit.first;
}

/// U28: the Incoming Load Card. One load, full screen: the route, how far the pickup is, the goods, the fare, a
/// ring counting down the accept time, a slide to accept at the fare, a way to send another price, and Skip.
/// The cards come from [LoadRadar] one after another; when this one is taken by someone else or its time is up,
/// the card says so for two seconds and the next one opens. Back counts as Skip.
class IncomingLoadScreen extends StatefulWidget {
  final LoadRadar radar;
  final ValueChanged<String> onAccepted;
  final String? preferredVehicleId;

  /// Tests give their own sources and clock.
  final Future<List<Vehicle>> Function()? vehicles;
  final Future<String> Function(Load load, Vehicle vehicle)? accept;
  final DateTime Function()? now;
  final Duration goneFor;

  const IncomingLoadScreen({super.key, required this.radar, required this.onAccepted, this.preferredVehicleId, this.vehicles, this.accept, this.now, this.goneFor = const Duration(seconds: 2)});

  @override
  State<IncomingLoadScreen> createState() => _IncomingLoadScreenState();
}

class _IncomingLoadScreenState extends State<IncomingLoadScreen> {
  RadarItem? _shown;
  CardGone? _gone;
  int _others = 0;
  bool _busy = false;
  bool _done = false; // accepted, skipped or bid: leaving
  Timer? _goneTimer;
  StreamSubscription<RadarState>? _sub;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _apply(widget.radar.state);
    _sub = widget.radar.states.listen(_apply);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _goneTimer?.cancel();
    super.dispose();
  }

  void _show(RadarItem? item, int others) {
    final isNew = item != null && item.key != _shown?.key;
    setState(() {
      _shown = item;
      _others = others;
    });
    if (isNew) FeedbackKit.alert();
  }

  void _apply(RadarState s) {
    if (!mounted || _done || _gone != null) return;
    final all = [if (s.current != null) s.current!, ...s.queue];
    final shown = _shown;
    if (shown == null) {
      if (s.current == null) return _leave();
      return _show(s.current, s.waiting);
    }
    final still = all.where((i) => i.key == shown.key);
    if (still.isNotEmpty) {
      // the same card, with the fresh time; the ones behind it are counted
      setState(() {
        _shown = still.first;
        _others = all.length - 1;
      });
      return;
    }
    _closeBy(shown.secondsLeft(_now()) <= 0 ? CardGone.timeUp : CardGone.taken);
  }

  void _closeBy(CardGone why) {
    FeedbackKit.alert();
    setState(() {
      _gone = why;
      _busy = false;
    });
    _goneTimer?.cancel();
    _goneTimer = Timer(widget.goneFor, _advance);
  }

  void _advance() {
    if (!mounted || _done) return;
    final next = widget.radar.state.current;
    setState(() {
      _gone = null;
      if (next == null) _shown = null;
    });
    if (next == null) return _leave();
    _show(next, widget.radar.state.waiting);
  }

  void _leave([String? bookingId]) {
    if (_done) return;
    _done = true;
    if (mounted) Navigator.of(context).pop(bookingId);
  }

  void _next(RadarItem item) {
    widget.radar.skip(item);
    final next = widget.radar.state.current;
    if (next == null) return _leave();
    _show(next, widget.radar.state.waiting);
  }

  Future<Vehicle?> _truck(Load load) async {
    final all = await (widget.vehicles ?? VehicleService.fetchMyActive)();
    return truckForLoad(all, load, preferredId: widget.preferredVehicleId, now: _now());
  }

  Future<void> _accept() async {
    final item = _shown;
    if (item == null || _busy) return;
    setState(() => _busy = true);
    try {
      final v = await _truck(item.load);
      if (v == null) {
        if (mounted) showSnack(context, tr(context, 'ilNoTruck'));
        return;
      }
      final id = await (widget.accept ?? (l, vh) => BookingService.accept(loadId: l.id, vehicle: vh))(item.load, v);
      if (!mounted) return;
      showSnack(context, tr(context, 'loadAccepted'));
      _leave(id);
      widget.onAccepted(id);
    } on LoadUnavailableException {
      if (mounted) _closeBy(CardGone.taken);
    } on AccountRestrictedException {
      if (mounted) showSnack(context, tr(context, 'accountRestricted'));
    } on DocsExpiredException {
      if (mounted) showSnack(context, tr(context, 'docsExpiredBlock'));
    } on VehicleBusyException {
      if (mounted) showSnack(context, tr(context, 'vehicleBusy'));
    } catch (e) {
      if (mounted) showSnack(context, errorText(context, e));
    } finally {
      if (mounted && _gone == null) setState(() => _busy = false);
    }
  }

  Future<void> _bid() async {
    final item = _shown;
    if (item == null || _busy) return;
    final v = await _truck(item.load);
    if (!mounted) return;
    if (v == null) return showSnack(context, tr(context, 'ilNoTruck'));
    final sent = await showDriverBidSheet(context, load: item.load, vehicle: v, pickupKm: item.km);
    if (!mounted || !sent) return;
    showSnack(context, tr(context, 'bsSent'));
    _next(item);
  }

  Future<void> _skip() async {
    final item = _shown;
    if (item == null || _busy) return;
    // The reason is asked, never needed: closing the sheet skips as well.
    await showAppSheet<void>(
      context,
      title: tr(context, 'ilSkipWhy'),
      builder: (ctx) => Wrap(spacing: DsSpace.s2, runSpacing: DsSpace.s2, children: [
        for (final (key, label) in const [('far', 'ilWhyFar'), ('low', 'ilWhyLow'), ('truck', 'ilWhyTruck'), ('other', 'ilWhyOther')])
          ActionChip(key: ValueKey('skip_$key'), label: Text(tr(ctx, label)), onPressed: () => Navigator.of(ctx).pop()),
      ]),
    );
    if (mounted && _shown?.key == item.key) _next(item);
  }

  Widget _fact(IconData icon, String text) {
    final c = context.ds;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DsSpace.s1),
      child: Row(children: [
        Icon(icon, size: 20, color: c.textMuted),
        const SizedBox(width: DsSpace.s2),
        Expanded(child: Text(text, style: DsType.body.copyWith(color: c.text))),
      ]),
    );
  }

  Widget _goneView() {
    final c = context.ds;
    return Center(
      key: const ValueKey('ilGone'),
      child: Padding(
        padding: const EdgeInsets.all(DsSpace.s8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(_gone == CardGone.taken ? Icons.person_off_outlined : Icons.timer_off_outlined, size: 56, color: c.textMuted),
          const SizedBox(height: DsSpace.s4),
          Text(tr(context, _gone == CardGone.taken ? 'uxTakenByOther' : 'ilTimeUp'), textAlign: TextAlign.center, style: DsType.title.copyWith(color: c.textStrong)),
        ]),
      ),
    );
  }

  Widget _card(RadarItem item) {
    final c = context.ds;
    final l = item.load;
    final fare = cardFarePaise(l);
    final tripKm = l.estimate?.distanceKm;
    final total = (item.endsAt.difference(item.opensAt).inSeconds).clamp(1, 600);
    return ListView(padding: const EdgeInsets.all(DsSpace.gutter), children: [
      Row(children: [
        Expanded(child: Text(tr(context, 'ilTitle'), style: DsType.headline.copyWith(color: c.textStrong))),
        CountdownRing(key: const ValueKey('ilRing'), endsAt: item.endsAt, totalSeconds: total, now: widget.now),
      ]),
      if (_others > 0) Text(trf(context, 'ilQueue', {'n': _others}), key: const ValueKey('ilQueue'), style: DsType.bodySmall.copyWith(color: c.textMuted)),
      const SizedBox(height: DsSpace.s4),
      AppCard(child: RouteRibbon(from: l.pickup, to: l.drop, distanceKm: tripKm?.round())),
      const SizedBox(height: DsSpace.s3),
      if (item.km != null) _fact(Icons.my_location_rounded, trf(context, 'ilPickupKm', {'n': item.km!})),
      if (tripKm != null && tripKm > 0) _fact(Icons.route_rounded, trf(context, 'ilTripKm', {'n': tripKm.round()})),
      _fact(Icons.inventory_2_outlined, '${l.cargoType} • ${formatNum(l.weight)} T'),
      _fact(Icons.local_shipping_outlined, vehicleTypeLabel(context, l.vehicleType)),
      const SizedBox(height: DsSpace.s3),
      if (fare != null) Text(formatPaise(fare), key: const ValueKey('ilFare'), textAlign: TextAlign.center, style: DsType.display.copyWith(color: c.textStrong)),
      const SizedBox(height: DsSpace.s4),
      if (fare != null) SlideToConfirm(key: const ValueKey('ilSlide'), label: trf(context, 'ilAcceptAt', {'price': formatPaise(fare)}), enabled: !_busy, resetKey: item.key, onConfirmed: _accept),
      if (fare != null) const SizedBox(height: DsSpace.s3),
      AppButton(key: const ValueKey('ilBid'), label: tr(context, 'ilSendPrice'), kind: AppButtonKind.secondary, onPressed: _busy ? null : _bid),
      const SizedBox(height: DsSpace.s2),
      AppButton(key: const ValueKey('ilSkip'), label: tr(context, 'ilSkip'), kind: AppButtonKind.tertiary, onPressed: _busy ? null : _skip),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final item = _shown;
    return PopScope(
      // Back is Skip: the card does not come back for this question.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_done && item != null && _gone == null) widget.radar.skip(item);
      },
      child: Scaffold(
        backgroundColor: context.ds.bg,
        body: SafeArea(child: _gone != null ? _goneView() : (item == null ? const SizedBox.shrink() : _card(item))),
      ),
    );
  }
}
