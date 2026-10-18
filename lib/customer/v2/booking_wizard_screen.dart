import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/constants/logistics.dart';
import '../../core/dispatch/dispatch_models.dart';
import '../../core/drafts/smart_defaults.dart';
import '../../core/errors/error_text.dart';
import '../../core/features/features.dart';
import '../../core/l10n/l10n.dart';
import '../../core/maps/road_distance.dart';
import '../../core/models/risk.dart';
import '../../core/models/vehicle_type.dart';
import '../../core/pilot/waitlist.dart';
import '../../core/pricing/route_rates.dart';
import '../../core/services/features_service.dart';
import '../../core/services/load_service.dart';
import '../../core/services/pricing_service.dart';
import '../../core/services/rate_limit_service.dart';
import '../../core/services/vehicle_type_service.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/ds/app_button.dart';
import '../../core/widgets/ds/app_top_bar.dart';
import '../../core/widgets/ds/fare_meter.dart';
import '../../core/widgets/ds/money_text.dart';
import '../../core/widgets/ds/route_ribbon.dart';
import '../../core/widgets/ds/sheet_kit.dart';
import '../../core/widgets/ds/slide_to_confirm.dart';
import '../../core/widgets/logistics_labels.dart';
import '../place_field.dart';
import 'booking_wizard_model.dart';

/// U19: the new booking, five questions one at a time (route, goods, truck, price and mode, review). One primary
/// action at the bottom, the answers are saved on the phone as the person goes, Back never loses them, and the
/// last step is a slide to confirm. It posts with the same `LoadService.post` as the old form, so every rule, limit
/// and check is the same. Pops with the id of the new load.
class BookWizardScreen extends StatefulWidget {
  /// A draft to start from (a repeat of an old trip). Without it the saved draft, if any, is offered.
  final WizardDraft? initial;

  /// Tests replace the posting; it returns the id of the new load.
  final Future<String> Function(WizardDraft d)? poster;

  /// Tests give the truck list and the usual price instead of the services.
  final List<VehicleTypeInfo>? vehicleTypes;
  final Future<RateRange?> Function(String pickup, String drop, String vehicleType)? rateSource;

  /// Tests: whether bid mode is offered; by default it follows the `dispatchV2` switch.
  final bool? bidAvailable;

  const BookWizardScreen({super.key, this.initial, this.poster, this.vehicleTypes, this.rateSource, this.bidAvailable});

  @override
  State<BookWizardScreen> createState() => _BookWizardScreenState();
}

class _BookWizardScreenState extends State<BookWizardScreen> {
  late WizardDraft _d = widget.initial ?? const WizardDraft();
  final _pickup = TextEditingController();
  final _drop = TextEditingController();
  final _price = TextEditingController();
  String? _errorKey;
  bool _saving = false;
  bool _restored = false;
  Timer? _saveTimer;
  Object _slideReset = 0;
  LastRoute? _last;
  Future<RateRange?>? _rate;
  String? _rateKey;

  List<VehicleTypeInfo> get _types => widget.vehicleTypes ?? VehicleTypeService.types;
  bool get _bid => widget.bidAvailable ?? FeaturesService.isOn(FeatureKey.dispatchV2);

  @override
  void initState() {
    super.initState();
    _pickup.text = _d.pickup;
    _drop.text = _d.drop;
    _pickup.addListener(_onRoute);
    _drop.addListener(_onRoute);
    if (widget.initial == null) _restoreDraft();
    SmartDefaults.lastRoute().then((r) {
      if (mounted) setState(() => _last = r);
    });
  }

  Future<void> _restoreDraft() async {
    final saved = await WizardDraftStore.load();
    if (saved == null || !mounted) return;
    setState(() {
      _d = saved;
      _pickup.text = saved.pickup;
      _drop.text = saved.drop;
      _restored = true;
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (!_saving) unawaited(WizardDraftStore.save(_d));
    _pickup.dispose();
    _drop.dispose();
    _price.dispose();
    super.dispose();
  }

  void _onRoute() {
    if (_pickup.text == _d.pickup && _drop.text == _d.drop) return;
    _change(_d.copyWith(pickup: _pickup.text, drop: _drop.text));
  }

  /// Every change goes through here: the draft is replaced, the error clears and the save is queued.
  void _change(WizardDraft next) {
    setState(() {
      _d = next;
      _errorKey = null;
    });
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), () => WizardDraftStore.save(_d));
  }

  void _go(int step) {
    _change(_d.copyWith(step: step));
    unawaited(WizardDraftStore.save(_d));
  }

  void _next() {
    final e = _d.stepError(_d.step);
    if (e != null) {
      setState(() => _errorKey = e);
      return;
    }
    _go(_d.step + 1);
  }

  void _back() {
    if (_d.step > 0) _go(_d.step - 1);
  }

  Future<String> _defaultPost(WizardDraft d) {
    final via = d.mode == LoadMode.scheduled ? d.scheduledAt : null;
    return LoadService.post(
      pickup: d.pickup,
      drop: d.drop,
      cargoType: d.cargo,
      weight: d.weightTons!,
      vehicleType: d.vehicleType!,
      budget: d.budgetRupees,
      pickupDate: via ?? DateTime.now(),
      notes: '',
      estimate: d.quote,
      distanceSource: RoadDistance.kmFor(d.route) != null ? DistanceSource.maps : DistanceSource.cities,
      scheduledAt: via,
      mode: d.mode,
    );
  }

  Future<void> _submit() async {
    final bad = _d.firstIncomplete();
    if (bad != null) {
      setState(() {
        _errorKey = _d.stepError(bad);
        _slideReset = Object();
      });
      _go(bad);
      return;
    }
    if (widget.poster == null) {
      final areas = await PilotAreas.refresh();
      final closed = areas.firstClosed([_d.pickup, _d.drop]);
      if (closed != null) {
        if (!mounted) return;
        setState(() => _slideReset = Object());
        await showNotServed(context, role: 'customer', closedCity: closed, from: _d.pickup, to: _d.drop);
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final id = await (widget.poster ?? _defaultPost)(_d);
      _saveTimer?.cancel();
      await WizardDraftStore.clear();
      unawaited(SmartDefaults.record(pickup: _d.pickup, drop: _d.drop, cargo: _d.cargo, weight: _d.weightTons!, vehicleType: _d.vehicleType!));
      if (!mounted) return;
      Navigator.of(context).pop(id);
    } catch (error) {
      if (!mounted) return;
      if (error is ProhibitedCargoException) {
        _fail(trf(context, 'prohibitedCargo', {'item': error.item}));
      } else if (error is AccountRestrictedException) {
        _fail(tr(context, 'accountRestricted'));
      } else if (error is RateLimitException) {
        _fail(trf(context, 'rateLimited', {'m': error.minutesLeft}));
      } else {
        _fail(errorText(context, error), retry: true);
      }
    }
  }

  void _fail(String message, {bool retry = false}) {
    if (!mounted) return;
    setState(() {
      _saving = false;
      _slideReset = Object();
    });
    if (retry) {
      showRetrySnack(context, message, _submit);
    } else {
      showSnack(context, message);
    }
  }

  // ---- steps ----

  Widget _routeStep() {
    final c = context.ds;
    final ready = _d.pickup.trim().length >= 2 && _d.drop.trim().length >= 2;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(tr(context, 'wzPickup'), style: DsType.label.copyWith(color: c.textMuted)),
      const SizedBox(height: DsSpace.s1),
      PlaceField(key: const ValueKey('wzPickupField'), controller: _pickup, icon: const Icon(Icons.trip_origin_rounded), myLocation: true),
      const SizedBox(height: DsSpace.s4),
      Text(tr(context, 'wzDrop'), style: DsType.label.copyWith(color: c.textMuted)),
      const SizedBox(height: DsSpace.s1),
      PlaceField(key: const ValueKey('wzDropField'), controller: _drop, icon: const Icon(Icons.place_rounded)),
      const SizedBox(height: DsSpace.s4),
      if (ready) RouteRibbon(key: const ValueKey('wzRibbon'), from: _d.pickup.trim(), to: _d.drop.trim(), distanceKm: _d.km),
      if (_last != null && !ready) ...[
        Text(tr(context, 'wzRecent'), style: DsType.label.copyWith(color: c.textMuted)),
        const SizedBox(height: DsSpace.s2),
        ActionChip(
          key: const ValueKey('wzLastRoute'),
          avatar: const Icon(Icons.history_rounded, size: 18),
          label: Text('${_last!.pickup} → ${_last!.drop}'),
          onPressed: () {
            _pickup.text = _last!.pickup;
            _drop.text = _last!.drop;
          },
        ),
      ],
    ]);
  }

  Widget _goodsStep() {
    final c = context.ds;
    final w = _d.weightTons ?? 2.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      QuickChipRow<String>(
        padding: EdgeInsets.zero,
        options: [for (final k in cargoTypes) (k, k)],
        selected: _d.cargo,
        onChanged: (v) => _change(_d.copyWith(cargo: v ?? _d.cargo)),
      ),
      const SizedBox(height: DsSpace.s5),
      Text(trf(context, 'wzWeight', {'w': formatNum(w)}), key: const ValueKey('wzWeightText'), style: DsType.title.copyWith(color: c.textStrong)),
      Slider(
        key: const ValueKey('wzWeightSlider'),
        value: w.clamp(WizardDraft.minWeight, WizardDraft.maxWeight),
        min: WizardDraft.minWeight,
        max: WizardDraft.maxWeight,
        divisions: ((WizardDraft.maxWeight - WizardDraft.minWeight) / 0.5).round(),
        label: formatNum(w),
        onChanged: (v) {
          final next = (v * 2).round() / 2;
          // A new weight may not fit the chosen truck any more: the choice is dropped, never kept silently.
          final keep = _d.vehicleType == null || (VehicleTypeService.byId(_d.vehicleType)?.fits(next) ?? true);
          _change(_d.copyWith(weightTons: () => next, vehicleType: keep ? null : () => null, pricePaise: () => null));
        },
      ),
    ]);
  }

  Widget _truckStep() {
    final c = context.ds;
    final w = _d.weightTons;
    final suggested = WizardDraft.suggest(w, _types);
    final km = _d.km;
    // The trucks that carry the load come first, the suggested one on top; the ones that are too small go last.
    final ordered = [..._types]..sort((a, b) {
        final fa = w == null || a.fits(w), fb = w == null || b.fits(w);
        if (fa != fb) return fa ? -1 : 1;
        if (suggested != null && (a.id == suggested.id) != (b.id == suggested.id)) return a.id == suggested.id ? -1 : 1;
        return a.maxTons.compareTo(b.maxTons);
      });
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final t in ordered)
        Builder(builder: (context) {
          final fits = w == null || t.fits(w);
          final selected = _d.vehicleType == t.id;
          final typical = km == null ? null : WizardDraftQuote.typical(t.id, km);
          return Padding(
            padding: const EdgeInsets.only(bottom: DsSpace.s2),
            child: Semantics(
              button: true,
              selected: selected,
              enabled: fits,
              child: Material(
                color: selected ? c.tint : c.surface,
                borderRadius: DsRadius.all(DsRadius.lg),
                child: InkWell(
                  key: ValueKey('wzTruck_${t.id}'),
                  borderRadius: DsRadius.all(DsRadius.lg),
                  onTap: fits ? () => _change(_d.copyWith(vehicleType: () => t.id, pricePaise: () => null)) : null,
                  child: Container(
                    padding: const EdgeInsets.all(DsSpace.s4),
                    decoration: BoxDecoration(borderRadius: DsRadius.all(DsRadius.lg), border: Border.all(color: selected ? c.primary : c.border, width: selected ? 2 : 1)),
                    child: Row(children: [
                      Icon(Icons.local_shipping_rounded, color: fits ? c.primary : c.textHint),
                      const SizedBox(width: DsSpace.s3),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(vehicleTypeLabel(context, t.id), style: DsType.subtitle.copyWith(color: fits ? c.textStrong : c.textHint)),
                          Text(fits ? trf(context, 'wzCapacity', {'t': formatNum(t.maxTons)}) : tr(context, 'wzTooSmall'), style: DsType.bodySmall.copyWith(color: c.textMuted)),
                          if (typical != null && fits) Padding(padding: const EdgeInsets.only(top: DsSpace.s1), child: MoneyText(typical, size: MoneySize.body)),
                          if (suggested?.id == t.id) Text(tr(context, 'wzSuggested'), style: DsType.label.copyWith(color: c.success)),
                        ]),
                      ),
                      if (selected) Padding(padding: const EdgeInsetsDirectional.only(start: DsSpace.s2), child: Icon(Icons.check_circle_rounded, color: c.primary)),
                    ]),
                  ),
                ),
              ),
            ),
          );
        }),
    ]);
  }

  Future<RateRange?>? _rateFor() {
    final v = _d.vehicleType;
    if (!FeaturesService.isOn(FeatureKey.rateRange) && widget.rateSource == null) return null;
    if (v == null) return null;
    final key = '${_d.pickup}|${_d.drop}|$v';
    if (_rateKey != key) {
      _rateKey = key;
      _rate = (widget.rateSource ?? RouteRates.fetch)(_d.pickup, _d.drop, v);
    }
    return _rate;
  }

  Widget _modeCard(LoadMode m, String title, String hint, IconData icon) {
    final c = context.ds;
    final on = _d.mode == m;
    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpace.s2),
      child: Semantics(
        button: true,
        selected: on,
        child: InkWell(
          key: ValueKey('wzMode_${m.value}'),
          borderRadius: DsRadius.all(DsRadius.lg),
          onTap: () => _change(_d.copyWith(mode: m)),
          child: Container(
            padding: const EdgeInsets.all(DsSpace.s4),
            decoration: BoxDecoration(
              color: on ? c.tint : c.surface,
              borderRadius: DsRadius.all(DsRadius.lg),
              border: Border.all(color: on ? c.primary : c.border, width: on ? 2 : 1),
            ),
            child: Row(children: [
              Icon(icon, color: c.primary),
              const SizedBox(width: DsSpace.s3),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: DsType.subtitle.copyWith(color: c.textStrong)),
                  Text(hint, style: DsType.bodySmall.copyWith(color: c.textMuted)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _pickWhen() async {
    final now = DateTime.now();
    final date = await showDatePicker(context: context, initialDate: _d.scheduledAt ?? now.add(const Duration(days: 1)), firstDate: now, lastDate: now.add(const Duration(days: 90)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_d.scheduledAt ?? now.add(const Duration(hours: 3))));
    if (time == null || !mounted) return;
    _change(_d.copyWith(scheduledAt: () => DateTime(date.year, date.month, date.day, time.hour, time.minute)));
  }

  Widget _priceStep() {
    final c = context.ds;
    final est = _d.estimatePaise;
    final value = _d.effectivePricePaise;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (est != null && value != null)
        FutureBuilder<RateRange?>(
          future: _rateFor(),
          builder: (context, snap) => FareMeter(
            key: const ValueKey('wzFareMeter'),
            estimatePaise: WizardDraft.roundTo10Rupees(est)!,
            valuePaise: value,
            usualLowPaise: snap.data?.low,
            usualHighPaise: snap.data?.high,
            onChanged: (p) => _change(_d.copyWith(pricePaise: () => p)),
          ),
        )
      else ...[
        Text(tr(context, 'wzNoQuote'), style: DsType.bodySmall.copyWith(color: c.textMuted)),
        const SizedBox(height: DsSpace.s2),
        TextField(
          key: const ValueKey('wzOwnPrice'),
          controller: _price,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: tr(context, 'wzYourPrice'), prefixText: '₹ '),
          onChanged: (t) {
            final rupees = int.tryParse(t.trim());
            _change(_d.copyWith(pricePaise: () => rupees == null || rupees <= 0 ? null : rupees * 100));
          },
        ),
      ],
      const SizedBox(height: DsSpace.s5),
      Semantics(header: true, child: Text(tr(context, 'wzModeTitle'), style: DsType.title.copyWith(color: c.textStrong))),
      const SizedBox(height: DsSpace.s2),
      _modeCard(LoadMode.instant, tr(context, 'wzModeInstant'), tr(context, 'wzModeInstantHint'), Icons.bolt_rounded),
      if (_bid) _modeCard(LoadMode.bid, tr(context, 'wzModeBid'), tr(context, 'wzModeBidHint'), Icons.gavel_rounded),
      _modeCard(LoadMode.scheduled, tr(context, 'wzModeSchedule'), tr(context, 'wzModeScheduleHint'), Icons.event_rounded),
      if (_d.mode == LoadMode.scheduled)
        Padding(
          padding: const EdgeInsets.only(top: DsSpace.s2),
          child: AppButton(
            key: const ValueKey('wzPickWhen'),
            label: _d.scheduledAt == null ? tr(context, 'wzPickDate') : formatDateTime(_d.scheduledAt!),
            kind: AppButtonKind.secondary,
            icon: Icons.schedule_rounded,
            onPressed: _pickWhen,
          ),
        ),
    ]);
  }

  Widget _reviewStep() {
    final c = context.ds;
    final price = _d.effectivePricePaise;
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: DsSpace.s1),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(k, style: DsType.bodySmall.copyWith(color: c.textMuted))),
            Flexible(child: Text(v, textAlign: TextAlign.end, style: DsType.body.copyWith(color: c.textStrong))),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      RouteRibbon(from: _d.pickup.trim(), to: _d.drop.trim(), distanceKm: _d.km),
      const SizedBox(height: DsSpace.s4),
      Container(
        padding: const EdgeInsets.all(DsSpace.s4),
        decoration: BoxDecoration(color: c.surface, borderRadius: DsRadius.all(DsRadius.lg), border: Border.all(color: c.border)),
        child: Column(children: [
          row(tr(context, 'wzQ2'), '${_d.cargo}, ${formatNum(_d.weightTons ?? 0)} T'),
          row(tr(context, 'wzQ3'), _d.vehicleType == null ? '-' : vehicleTypeLabel(context, _d.vehicleType!)),
          row(tr(context, 'wzModeTitle'), tr(context, switch (_d.mode) { LoadMode.instant => 'wzModeInstant', LoadMode.bid => 'wzModeBid', LoadMode.scheduled => 'wzModeSchedule' })),
          if (_d.mode == LoadMode.scheduled && _d.scheduledAt != null) row(tr(context, 'wzWhen'), formatDateTime(_d.scheduledAt!)),
        ]),
      ),
      const SizedBox(height: DsSpace.s4),
      Text(tr(context, 'wzYourPrice'), style: DsType.label.copyWith(color: c.textMuted)),
      if (price != null) MoneyText(price, size: MoneySize.display, key: const ValueKey('wzReviewPrice')),
      const SizedBox(height: DsSpace.s2),
      Text(trf(context, 'wzTerms', {'app': AppInfo.name}), style: DsType.caption.copyWith(color: c.textMuted)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final last = _d.step == WizardDraft.lastStep;
    final titleKey = ['wzQ1', 'wzQ2', 'wzQ3', 'wzQ4', 'wzQ5'][_d.step];
    final body = [_routeStep, _goodsStep, _truckStep, _priceStep, _reviewStep][_d.step]();
    return PopScope(
      canPop: _d.step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppTopBar(title: tr(context, 'wzTitle'), onBack: _d.step == 0 ? null : _back),
        body: SafeArea(
          child: Column(children: [
            Semantics(
              label: trf(context, 'wzStepOf', {'n': _d.step + 1, 'm': WizardDraft.lastStep + 1}),
              child: LinearProgressIndicator(key: const ValueKey('wzProgress'), value: (_d.step + 1) / (WizardDraft.lastStep + 1), minHeight: 4),
            ),
            Expanded(
              child: SingleChildScrollView(
                key: ValueKey('wzStep${_d.step}'),
                padding: const EdgeInsets.all(DsSpace.gutter),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(trf(context, 'wzStepOf', {'n': _d.step + 1, 'm': WizardDraft.lastStep + 1}), style: DsType.caption.copyWith(color: c.textMuted)),
                  const SizedBox(height: DsSpace.s1),
                  Semantics(header: true, child: Text(tr(context, titleKey), style: DsType.headline.copyWith(color: c.textStrong))),
                  if (_restored && _d.step == 0)
                    Padding(padding: const EdgeInsets.only(top: DsSpace.s1), child: Text(tr(context, 'wzDraftBack'), key: const ValueKey('wzDraftBack'), style: DsType.bodySmall.copyWith(color: c.textMuted))),
                  const SizedBox(height: DsSpace.s4),
                  body,
                  if (_errorKey != null)
                    Padding(
                      padding: const EdgeInsets.only(top: DsSpace.s3),
                      child: Row(children: [
                        Icon(Icons.error_outline_rounded, color: c.error, size: 20),
                        const SizedBox(width: DsSpace.s2),
                        Expanded(child: Text(tr(context, _errorKey!), key: const ValueKey('wzError'), style: DsType.bodySmall.copyWith(color: c.error))),
                      ]),
                    ),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(DsSpace.gutter, DsSpace.s2, DsSpace.gutter, DsSpace.s4),
              child: last
                  ? SlideToConfirm(key: const ValueKey('wzSlide'), label: tr(context, 'wzBookSlide'), enabled: !_saving, resetKey: _slideReset, onConfirmed: _submit)
                  : Row(children: [
                      if (_d.step > 0) ...[
                        Expanded(flex: 2, child: AppButton(key: const ValueKey('wzBack'), label: tr(context, 'wzBack'), kind: AppButtonKind.tertiary, onPressed: _back)),
                        const SizedBox(width: DsSpace.s3),
                      ],
                      Expanded(flex: 3, child: AppButton(key: const ValueKey('wzNext'), label: tr(context, 'wzNext'), big: true, onPressed: _next)),
                    ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The typical price of a truck type on a route, for the cards of step 3.
class WizardDraftQuote {
  WizardDraftQuote._();

  static int? typical(String vehicleType, int km) {
    try {
      return WizardDraft.roundTo10Rupees(PricingService.quote(vehicleType: vehicleType, distanceKm: km).total);
    } catch (_) {
      return null;
    }
  }
}
