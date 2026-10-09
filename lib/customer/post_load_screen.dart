import '../core/errors/error_text.dart';
import '../core/drafts/smart_defaults.dart';
import 'dart:async';

import '../core/drafts/load_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/constants/cancel_reasons.dart';
import '../core/constants/logistics.dart';
import '../core/services/load_service.dart';
import 'matching_vehicles_line.dart';
import '../core/widgets/common.dart';
import 'place_field.dart';
import '../core/models/risk.dart';
import '../core/l10n/l10n.dart';
import '../core/widgets/feature_gate.dart';
import '../core/features/features.dart';
import '../core/services/vehicle_type_service.dart';
import '../core/widgets/logistics_labels.dart';
import '../core/services/pricing_service.dart';
import '../core/pricing/fare_calculator.dart';
import '../core/widgets/fare_breakdown.dart';
import '../core/widgets/trip_cost_widgets.dart';
import '../core/constants/prohibited_cargo.dart';
import '../core/models/load.dart';
import '../core/widgets/booking_type_widgets.dart';
import 'saved_place_picker.dart';
import '../core/models/ledger_entry.dart';
import '../core/documents/payment_card.dart';
import 'trade_details_section.dart';
import 'offers_section.dart';
import '../core/scheduling/schedule.dart';
import '../core/offers/promo.dart';
import '../core/services/offers_switch_service.dart';
import '../core/services/rewards_service.dart';
import '../core/services/business_service.dart';
import '../core/services/business_ops_service.dart';
import '../core/models/recurring.dart';
import '../core/models/repeat.dart';
import '../core/services/recurring_service.dart';
import '../core/services/repeat_service.dart';
import '../core/services/rate_limit_service.dart';
import '../core/pilot/waitlist.dart';

/// Customer form to post a load. Pops with `true` once posted.
/// [repostFrom] prefills everything except the pickup date.
class PostLoadScreen extends StatefulWidget {
  final Load? repostFrom;

  /// Reserve the load for this driver (from an accepted truck request).
  final String? invitedDriverId;

  /// Starts on this vehicle type (Book Bike).
  final String? initialVehicleType;

  /// Pre-filled from the assistant (all optional).
  final String? initialPickup;
  final String? initialDrop;
  final String? initialWeight;

  /// A repeating load that came due: its pickup date starts at [dueDate] and
  /// it moves to the next date once posted.
  final RecurringLoad? recurring;
  final DateTime? dueDate;

  const PostLoadScreen({super.key, this.repostFrom, this.invitedDriverId, this.initialVehicleType, this.initialPickup, this.initialDrop, this.initialWeight, this.recurring, this.dueDate});

  @override
  State<PostLoadScreen> createState() => _PostLoadScreenState();
}

class _PostLoadScreenState extends State<PostLoadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pickupCtrl = TextEditingController();
  final _dropCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _costCenterCtrl = TextEditingController();
  String? _businessId;

  /// Approved drivers of the company (BIZ9); "only them" limits who can accept.
  List<String> _pool = const [];
  bool _poolOnly = false;
  final _distanceCtrl = TextEditingController();
  final _containerCtrl = TextEditingController();
  final _sealCtrl = TextEditingController();
  String? _branchId;
  String _cargoType = cargoTypes.first;
  String _vehicleType = '14ft';
  DateTime? _pickupDate;
  String _slot = PickupSlot.any;
  String _paymentMode = PaymentMode.cash;
  bool _saving = false;
  OffersChoice _offers = const OffersChoice();
  TimeOfDay? _pickupTime;
  bool _fragile = false;
  bool _instant = false;
  String _visibility = LoadVisibility.public;
  String _repeat = '';
  bool _highValue = false;
  String _bookingType = BookingType.freight;
  int _helpers = 0;
  int _rentalHours = rentalHourOptions.first;
  final _itemsCtrl = TextEditingController();
  final _floorCtrl = TextEditingController(text: '0');
  bool _hasLift = true;
  bool _packing = false;
  final List<TextEditingController> _extraPickups = [];
  final List<TextEditingController> _extraDrops = [];

  @override
  void dispose() {
    _draftTimer?.cancel();
    _pickupCtrl.dispose();
    _dropCtrl.dispose();
    _weightCtrl.dispose();
    _budgetCtrl.dispose();
    _valueCtrl.dispose();
    _notesCtrl.dispose();
    _costCenterCtrl.dispose();
    _distanceCtrl.dispose();
    _containerCtrl.dispose();
    _sealCtrl.dispose();
    _itemsCtrl.dispose();
    _floorCtrl.dispose();
    for (final c in [..._extraPickups, ..._extraDrops]) {
      c.dispose();
    }
    super.dispose();
  }

  /// What was typed when the screen opened; leaving with something else typed asks first.
  List<String> _initial = const [];

  // ---- draft (Task 15): kept on this phone, saved a moment after typing stops ----
  LoadDraft? _draft;
  Timer? _draftTimer;

  // ---- smart defaults (Task 16) ----
  LastRoute? _lastRoute;
  List<GoodsPreset> _presets = const [];

  LoadDraft _draftNow() => LoadDraft(
        pickup: _pickupCtrl.text,
        drop: _dropCtrl.text,
        cargoType: _cargoType,
        weight: _weightCtrl.text,
        vehicleType: _vehicleType,
        budget: _budgetCtrl.text,
        notes: _notesCtrl.text,
        pickupDate: _pickupDate == null ? '' : DateUtils.dateOnly(_pickupDate!).toIso8601String().substring(0, 10),
        savedAt: DateTime.now(),
      );

  void _scheduleDraft() {
    // While the banner waits for a decision, typing must not overwrite the saved draft.
    if (_saving || _draftLocked || _draft != null) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 1500), () => LoadDraftStore.save(_draftNow()));
  }

  /// Set once the load is posted or the draft was deleted on purpose, so a late timer cannot bring it back.
  bool _draftLocked = false;

  void _applyDraft(LoadDraft d) {
    setState(() {
      _pickupCtrl.text = d.pickup;
      _dropCtrl.text = d.drop;
      _weightCtrl.text = d.weight;
      _budgetCtrl.text = d.budget;
      _notesCtrl.text = d.notes;
      if (cargoTypes.contains(d.cargoType)) _cargoType = d.cargoType;
      if (d.vehicleType.isNotEmpty) _vehicleType = d.vehicleType;
      final day = d.pickupDay;
      if (day != null && !day.isBefore(DateUtils.dateOnly(DateTime.now()))) _pickupDate = day;
      _draft = null;
    });
  }

  Future<void> _deleteDraft() async {
    _draftLocked = true;
    _draftTimer?.cancel();
    await LoadDraftStore.clear();
    if (mounted) setState(() => _draft = null);
  }

  List<String> _typedNow() => [_pickupCtrl.text.trim(), _dropCtrl.text.trim(), _weightCtrl.text.trim(), _notesCtrl.text.trim(), _budgetCtrl.text.trim()];

  bool get _dirty {
    if (_saving) return false;
    final now = _typedNow();
    for (var i = 0; i < now.length; i++) {
      if (i >= _initial.length || _initial[i] != now[i]) return true;
    }
    return false;
  }

  Future<void> _confirmLeave() async {
    final leave = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr(c, 'discardTitle')),
        content: Text(tr(c, 'discardBody')),
        actions: [
          TextButton(key: const ValueKey('keepEditing'), onPressed: () => Navigator.pop(c, null), child: Text(tr(c, 'keepEditing'))),
          TextButton(key: const ValueKey('saveDraftLeave'), onPressed: () => Navigator.pop(c, 'save'), child: Text(tr(c, 'draftSave'))),
          FilledButton(key: const ValueKey('discardLoad'), onPressed: () => Navigator.pop(c, 'discard'), child: Text(tr(c, 'discard'))),
        ],
      ),
    );
    if (leave == null || !mounted) return;
    _draftTimer?.cancel();
    final messenger = ScaffoldMessenger.of(context);
    final saved = tr(context, 'draftSaved');
    // The draft is written in the background so leaving never waits for the disk.
    if (leave == 'save') {
      unawaited(LoadDraftStore.save(_draftNow()));
      messenger.showSnackBar(SnackBar(content: Text(saved)));
    } else {
      _draftLocked = true;
      unawaited(LoadDraftStore.clear());
    }
    if (mounted) Navigator.of(context).pop();
  }

  TextEditingController _stopCtrl([String text = '']) => TextEditingController(text: text)..addListener(_requote);

  void _prefill(Load l) {
    _pickupCtrl.text = l.pickup;
    _dropCtrl.text = l.drop;
    _weightCtrl.text = formatNum(l.weight);
    if (l.budget != null) _budgetCtrl.text = formatNum(l.budget!);
    _notesCtrl.text = l.notes;
    if (cargoTypes.contains(l.cargoType)) _cargoType = l.cargoType;
    _vehicleType = l.vehicleType;
    _slot = l.pickupSlot;
    _paymentMode = l.paymentMode;
    if (l.distanceSource == DistanceSource.manual && l.estimate != null) _distanceCtrl.text = '${l.estimate!.distanceKm}';
    _bookingType = l.bookingType;
    _fragile = l.fragile;
    _highValue = l.highValue;
    if ((l.declaredValuePaise ?? 0) > 0) _valueCtrl.text = '${l.declaredValuePaise! ~/ 100}';
    _helpers = l.helpers;
    _rentalHours = l.rentalHours ?? _rentalHours;
    final m = l.movers;
    if (m != null) {
      _itemsCtrl.text = [for (final e in m.items.entries) '${e.key} x${e.value}'].join('\n');
      _floorCtrl.text = '${m.floor}';
      _hasLift = m.hasLift;
      _packing = m.packingNeeded;
    }
    _extraPickups.addAll(l.extraPickups.map(_stopCtrl));
    _extraDrops.addAll(l.extraDrops.map(_stopCtrl));
  }

  Future<void> _fillFromSaved(TextEditingController c) async {
    final place = await pickSavedPlace(context);
    if (place != null) c.text = savedPlaceText(place);
  }

  Widget _savedPlaceButton(TextEditingController c) => IconButton(
        tooltip: tr(context, 'savedPlaces'),
        icon: const Icon(Icons.bookmark_border_rounded),
        onPressed: () => _fillFromSaved(c),
      );

  Widget _stopField(TextEditingController c, String label, List<TextEditingController> list, {required bool pickup}) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: TextFormField(
        controller: c,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(pickup ? Icons.trip_origin_rounded : Icons.location_on_outlined,
              color: pickup ? AppColors.success : Colors.redAccent),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _savedPlaceButton(c),
              IconButton(
                tooltip: tr(context, 'removeStop'),
                icon: const Icon(Icons.remove_circle_outline_rounded),
                onPressed: () => setState(() {
                  list.remove(c);
                  c.dispose();
                }),
              ),
            ],
          ),
        ),
        validator: _requiredText, inputFormatters: [LengthLimitingTextInputFormatter(100)]),
    );
  }

  Widget _addStopButton(List<TextEditingController> list, String key, String textKey) {
    if (list.length >= maxStopsPerSide - 1) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: ValueKey(key),
        onPressed: () => setState(() => list.add(_stopCtrl())),
        icon: const Icon(Icons.add_rounded, size: 18),
        label: Text(tr(context, textKey)),
      ),
    );
  }

  String? _notesValidator(String? v) {
    final banned = prohibitedCargoMatch(v ?? '');
    return banned == null ? null : trf(context, 'prohibitedCargo', {'item': banned});
  }

  @override
  void initState() {
    super.initState();
    if (widget.repostFrom != null) _prefill(widget.repostFrom!);
    if (widget.initialVehicleType != null) _vehicleType = widget.initialVehicleType!;
    if (widget.initialPickup != null) _pickupCtrl.text = widget.initialPickup!;
    if (widget.initialDrop != null) _dropCtrl.text = widget.initialDrop!;
    if (widget.initialWeight != null) _weightCtrl.text = widget.initialWeight!;
    if (widget.dueDate != null) {
      final today = DateUtils.dateOnly(DateTime.now());
      final due = DateUtils.dateOnly(widget.dueDate!);
      _pickupDate = due.isBefore(today) ? today : due;
    }
    _initial = _typedNow();
    final plainOpen = widget.repostFrom == null && widget.initialPickup == null && widget.initialDrop == null && widget.initialWeight == null && widget.initialVehicleType == null && widget.dueDate == null;
    if (plainOpen) {
      SmartDefaults.lastRoute().then((r) {
        if (mounted && r != null) setState(() => _lastRoute = r);
      });
      SmartDefaults.presets().then((p) {
        if (mounted) setState(() => _presets = p);
      });
      LoadDraftStore.load().then((d) {
        if (mounted && d != null) setState(() => _draft = d);
      });
    }
    if (plainOpen) {
      for (final c in [_pickupCtrl, _dropCtrl, _weightCtrl, _budgetCtrl, _notesCtrl]) {
        c.addListener(_scheduleDraft);
      }
    }
    BusinessService.postingBusinessId().then((id) {
      if (mounted && id != null) setState(() => _businessId = id);
      if (id != null) {
        BusinessOpsService.poolIds(id).then((ids) {
          if (mounted) setState(() => _pool = ids.take(LoadVisibility.maxAllowed).toList());
        }, onError: (_) {});
      }
    }, onError: (_) {});
    // Re-quote as the route or distance changes.
    for (final c in [_pickupCtrl, _dropCtrl, _distanceCtrl, _weightCtrl, _itemsCtrl, _floorCtrl]) {
      c.addListener(_requote);
    }
  }

  void _requote() => setState(() {});

  int? get _manualKm {
    final n = int.tryParse(_distanceCtrl.text.trim());
    return (n != null && n > 0 && n <= 5000) ? n : null;
  }

  List<String> get _route => [
        _pickupCtrl.text,
        for (final c in _extraPickups) c.text,
        for (final c in _extraDrops) c.text,
        _dropCtrl.text,
      ];

  int? get _autoKm => PricingService.estimateRouteKm(_route);

  MoversDetails? get _movers {
    final items = MoversDetails.parseItems(_itemsCtrl.text);
    if (items == null || items.isEmpty) return null;
    return MoversDetails(
      items: items,
      floor: (int.tryParse(_floorCtrl.text.trim()) ?? 0).clamp(0, 50),
      hasLift: _hasLift,
      packingNeeded: _packing,
    );
  }

  /// Quote for the current form, or null without what the type needs (a
  /// usable distance for freight and movers, items for movers).
  FareBreakdown? get _quote {
    if (_bookingType == BookingType.rental) {
      return PricingService.quoteRental(vehicleType: _vehicleType, hours: _rentalHours, helpers: _helpers);
    }
    final km = _manualKm ?? _autoKm;
    if (km == null) return null;
    final movers = _bookingType == BookingType.movers ? _movers : null;
    if (_bookingType == BookingType.movers && movers == null) return null;
    return PricingService.quote(
      vehicleType: _vehicleType,
      distanceKm: km,
      extraStops: _extraPickups.length + _extraDrops.length,
      helpers: _helpers,
      movers: movers,
      at: _scheduledAt ?? _pickupDate?.add(const Duration(hours: 12)),
    );
  }

  Widget _estimateCard() {
    final auto = _autoKm;
    final quote = _quote;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_bookingType == BookingType.rental)
            Text(
              trf(context, 'rentalIncludes', {
                'km': PricingService.rentalIncludedKm(_vehicleType, _rentalHours),
                'hours': _rentalHours,
              }),
              key: const ValueKey('rentalIncludes'),
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            )
          else
            Text(
              auto != null ? trf(context, 'distanceAuto', {'km': auto}) : tr(context, 'distanceUnknown'),
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          if (_bookingType != BookingType.rental) const SizedBox(height: 10),
          if (_bookingType != BookingType.rental) TextFormField(
            key: const ValueKey('distanceKm'),
            controller: _distanceCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [LengthLimitingTextInputFormatter(10), FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(prefixIcon: const Icon(Icons.straighten_rounded), labelText: tr(context, 'distanceOverride')),
            validator: (v) {
              final t = v?.trim() ?? '';
              if (t.isEmpty) return null;
              return _manualKm == null ? tr(context, 'invalidNumber') : null;
            },
          ),
          if (quote != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(context, 'fareTotal'), style: TextStyle(color: AppColors.muted, fontSize: 12)),
                      Text(formatPaise(quote.total),
                          key: const ValueKey('fareTotal'),
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.title)),
                    ],
                  ),
                ),
                TextButton(onPressed: () => showFareBreakdown(context, quote), child: Text(tr(context, 'viewBreakdown'))),
              ],
            ),
          ],
          if (quote != null && _bookingType != BookingType.rental && (_manualKm ?? auto) != null) ...[
            const SizedBox(height: 12),
            TripCostCard(
              cost: tripCostFor(farePaise: quote.total, km: (_manualKm ?? auto)!, vehicleType: _vehicleType, from: _pickupCtrl.text, to: _dropCtrl.text),
            ),
          ],
          const SizedBox(height: 6),
          Text(tr(context, 'estimateNote'), style: TextStyle(color: AppColors.faint, fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _pickDate(FormFieldState<DateTime> field) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _pickupDate ?? today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 90)),
    );
    if (picked == null) return;
    setState(() {
      _pickupDate = picked;
      if (picked != today) _instant = false;
    });
    field.didChange(picked);
  }

  Future<void> _pickTime() async {
    final soon = DateTime.now().add(const Duration(hours: 2));
    final t = await showTimePicker(context: context, initialTime: _pickupTime ?? TimeOfDay(hour: soon.hour, minute: 0));
    if (t != null && mounted) setState(() => _pickupTime = t);
  }

  /// Declared goods value in paise, or null when the field is empty.
  int? get _declaredValuePaise {
    final t = _valueCtrl.text.trim();
    final rupees = int.tryParse(t);
    return rupees == null ? null : rupees * 100;
  }

  /// Pickup date + chosen time, or null when no exact time is set.
  DateTime? get _scheduledAt {
    final d = _pickupDate, t = _pickupTime;
    return d == null || t == null ? null : DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  Future<void> _saveTemplate() async {
    if (!_formKey.currentState!.validate()) return;
    final name = await showDialog<String>(context: context, builder: (_) => const _TemplateNameDialog());
    if (name == null || name.trim().isEmpty) return;
    final budgetText = _budgetCtrl.text.trim();
    try {
      await RepeatService.saveTemplate(LoadTemplate(
        id: '',
        name: name,
        pickup: _pickupCtrl.text.trim(),
        drop: _dropCtrl.text.trim().isEmpty ? _pickupCtrl.text.trim() : _dropCtrl.text.trim(),
        cargoType: _cargoType,
        weight: num.parse(_weightCtrl.text.trim()),
        vehicleType: _vehicleType,
        budget: budgetText.isEmpty ? null : num.parse(budgetText),
        notes: _notesCtrl.text.trim(),
        pickupSlot: _slot,
        fragile: _fragile,
        highValue: _highValue,
        costCenter: _businessId == null ? null : _costCenterCtrl.text.trim(),
      ));
      if (mounted) showSnack(context, tr(context, 'templateSaved'));
    } on TemplateLimitException {
      if (mounted) showSnack(context, tr(context, 'templateLimit'));
    }
  }

  /// Repeating loads: a new schedule from this form, or the due one moves on.
  Future<void> _afterPosted() async {
    try {
      if (widget.recurring != null) {
        await RecurringService.advance(widget.recurring!, from: widget.dueDate ?? widget.recurring!.nextDueAt);
      } else if (_repeat.isNotEmpty) {
        final budgetText = _budgetCtrl.text.trim();
        await RecurringService.create(
          LoadTemplate(
            id: '',
            name: _repeatName(),
            pickup: _pickupCtrl.text.trim(),
            drop: _dropCtrl.text.trim().isEmpty ? _pickupCtrl.text.trim() : _dropCtrl.text.trim(),
            cargoType: _cargoType,
            weight: num.parse(_weightCtrl.text.trim()),
            vehicleType: _vehicleType,
            budget: budgetText.isEmpty ? null : num.parse(budgetText),
            notes: _notesCtrl.text.trim(),
            pickupSlot: _slot,
            fragile: _fragile,
            highValue: _highValue,
            costCenter: _businessId == null ? null : _costCenterCtrl.text.trim(),
          ),
          _repeat,
          first: _scheduledAt ?? _pickupDate!,
        );
      }
    } on RecurringLimitException {
      if (mounted) showSnack(context, tr(context, 'repeatLimit'));
    } catch (_) {
      // The load itself is posted; the schedule can be set up again.
    }
  }

  String _repeatName() {
    final a = _pickupCtrl.text.trim();
    final b = _dropCtrl.text.trim().isEmpty ? a : _dropCtrl.text.trim();
    final n = '$a - $b';
    return n.length <= 40 ? n : n.substring(0, 40);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final when = _scheduledAt;
    if (_pickupTime != null && when != null) {
      final rules = PricingService.config.schedule;
      final problem = Schedule.check(when, DateTime.now(), rules);
      if (problem != null) {
        showSnack(context, problem == ScheduleProblem.tooSoon
            ? trf(context, 'scheduleTooSoon', {'m': rules.minMinutes})
            : trf(context, 'scheduleTooFar', {'d': rules.maxDays}));
        return;
      }
    }
    final areas = await PilotAreas.refresh();
    final closed = areas.firstClosed([_pickupCtrl.text, _dropCtrl.text]);
    if (closed != null) {
      if (!mounted) return;
      await showNotServed(context, role: 'customer', closedCity: closed, from: _pickupCtrl.text, to: _dropCtrl.text.trim().isEmpty ? _pickupCtrl.text : _dropCtrl.text);
      return;
    }
    setState(() => _saving = true);
    try {
      final budgetText = _budgetCtrl.text.trim();
      final quote = _quote;
      // Number the promo slot for the final total, and decide the credits.
      PromoApplication? promo;
      var credits = 0;
      if (quote != null) {
        final offers = allowedOffers(_offers, OffersSwitchService.current);
        if (offers.promo != null) promo = await RewardsService.reserve(offers.promo!.code, quote.total);
        if (offers.useCredits) {
          credits = creditsToSpend(
              total: quote.total, promo: offers.promo, creditsBalance: await RewardsService.balance(), useCredits: true);
        }
      }
      var allowed = const <String>[];
      if (_visibility == LoadVisibility.favourites) {
        allowed = (await RepeatService.favouriteIds()).take(LoadVisibility.maxAllowed).toList();
        if (allowed.isEmpty) {
          if (!mounted) return;
          setState(() => _saving = false);
          showSnack(context, tr(context, 'visNoFavourites'));
          return;
        }
      } else if (_visibility == LoadVisibility.invite && widget.invitedDriverId != null) {
        allowed = [widget.invitedDriverId!];
      }
      var visibility = _visibility;
      if (_poolOnly && _businessId != null && _pool.isNotEmpty && _visibility == LoadVisibility.public) {
        visibility = LoadVisibility.invite;
        allowed = _pool;
      }
      final budgetPaise = budgetText.isEmpty ? (quote?.total ?? 0) : (num.parse(budgetText) * 100).round();
      final waits = _businessId != null && await BusinessOpsService.approvalNeeded(_businessId!, budgetPaise);
      await LoadService.post(
        visibility: visibility,
        allowedDriverIds: allowed,
        instant: _instant,
        promo: promo,
        creditsUsedPaise: credits,
        fragile: _fragile,
        highValue: _highValue,
        declaredValuePaise: _declaredValuePaise,
        scheduledAt: _scheduledAt,
        invitedDriverId: widget.invitedDriverId,
        businessId: _businessId,
        costCenter: _businessId == null ? null : _costCenterCtrl.text,
        pickup: _pickupCtrl.text,
        drop: _dropCtrl.text.trim().isEmpty ? _pickupCtrl.text : _dropCtrl.text,
        cargoType: _cargoType,
        weight: num.parse(_weightCtrl.text.trim()),
        vehicleType: _vehicleType,
        budget: budgetText.isEmpty ? null : num.parse(budgetText),
        pickupDate: _pickupDate!,
        notes: _notesCtrl.text,
        bookingType: _bookingType,
        helpers: _helpers,
        rentalHours: _bookingType == BookingType.rental ? _rentalHours : null,
        movers: _bookingType == BookingType.movers ? _movers : null,
        estimate: _quote,
        distanceSource: _manualKm != null ? DistanceSource.manual : DistanceSource.cities,
        extraPickups: [for (final c in _extraPickups) c.text],
        extraDrops: [for (final c in _extraDrops) c.text],
        pickupSlot: _slot,
        paymentMode: _paymentMode,
        containerNumber: _containerCtrl.text,
        sealNumber: _sealCtrl.text,
        branchId: _branchId,
      );
      if (!mounted) return;
      await _afterPosted();
      if (!mounted) return;
      showSnack(context, tr(context, waits ? 'bizSentForApproval' : 'loadPosted'));
      _draftLocked = true;
      _draftTimer?.cancel();
      unawaited(LoadDraftStore.clear());
      final w = num.tryParse(_weightCtrl.text.trim());
      if (w != null) unawaited(SmartDefaults.record(pickup: _pickupCtrl.text, drop: _dropCtrl.text, cargo: _cargoType, weight: w, vehicleType: _vehicleType));
      Navigator.of(context).pop(true);
    } on PromoException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, e.problem == PromoProblem.belowMinimum && e.minOrderPaise != null
          ? trf(context, 'promoBelowMinimum', {'min': formatPaise(e.minOrderPaise!)})
          : tr(context, promoProblemKey(e.problem)));
    } on ProhibitedCargoException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, trf(context, 'prohibitedCargo', {'item': e.item}));
    } on AccountRestrictedException {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, tr(context, 'accountRestricted'));
    } on RateLimitException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, trf(context, 'rateLimited', {'m': e.minutesLeft}));
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showRetrySnack(context, errorText(context, error), _submit);
    }
  }

  String? _requiredText(String? v) => (v == null || v.trim().length < 2) ? tr(context, 'fieldRequired') : null;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        title: Text(tr(context, 'postLoad'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FeatureGate(
                  featureKey: FeatureKey.rentalMovers,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    FieldLabel(tr(context, 'bookingTypeLabel')),
                    BookingTypePicker(value: _bookingType, onChanged: (t) => setState(() => _bookingType = t)),
                    const SizedBox(height: 18),
                  ]),
                ),
                if (_draft != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: AppCard(
                      key: const ValueKey('draftBanner'),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tr(context, 'draftTitle'), style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text('${_draft!.pickup.trim().isEmpty ? '...' : _draft!.pickup} → ${_draft!.drop.trim().isEmpty ? '...' : _draft!.drop}', style: TextStyle(color: AppColors.muted)),
                        const SizedBox(height: 6),
                        Wrap(spacing: 8, children: [
                          FilledButton(key: const ValueKey('draftResume'), onPressed: () => _applyDraft(_draft!), child: Text(tr(context, 'draftResume'))),
                          TextButton(key: const ValueKey('draftDelete'), onPressed: _deleteDraft, child: Text(tr(context, 'draftDelete'))),
                        ]),
                      ]),
                    ),
                  ),
                _StepHeader(1, 'wizRoute'),
                FieldLabel(tr(context, 'pickupLocation')),
                PlaceField(
                  controller: _pickupCtrl,
                  icon: const Icon(Icons.trip_origin_rounded, color: AppColors.success),
                  myLocation: true,
                  trailing: _savedPlaceButton(_pickupCtrl),
                  validator: _requiredText,
                ),
                if (_lastRoute != null && _pickupCtrl.text.trim().isEmpty && _dropCtrl.text.trim().isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: ActionChip(
                      key: const ValueKey('sdLastRoute'),
                      avatar: const Icon(Icons.history_rounded, size: 18),
                      label: Text(trf(context, 'sdLast', {'from': _lastRoute!.pickup, 'to': _lastRoute!.drop})),
                      onPressed: () => setState(() {
                        _pickupCtrl.text = _lastRoute!.pickup;
                        _dropCtrl.text = _lastRoute!.drop;
                      }),
                    ),
                  ),
                for (final (i, c) in _extraPickups.indexed)
                  _stopField(c, trf(context, 'pickupStopN', {'n': i + 2}), _extraPickups, pickup: true),
                _addStopButton(_extraPickups, 'addPickupStop', 'addPickupStop'),
                const SizedBox(height: 8),
                FieldLabel(tr(context, 'dropLocation')),
                for (final (i, c) in _extraDrops.indexed)
                  _stopField(c, trf(context, 'dropStopN', {'n': i + 1}), _extraDrops, pickup: false),
                if (_extraDrops.isNotEmpty) const SizedBox(height: 10),
                PlaceField(
                  controller: _dropCtrl,
                  icon: const Icon(Icons.location_on_rounded, color: Colors.redAccent),
                  trailing: _savedPlaceButton(_dropCtrl),
                  validator: (v) => _bookingType == BookingType.rental ? null : _requiredText(v),
                ),
                _addStopButton(_extraDrops, 'addDropStop', 'addDropStop'),
                const SizedBox(height: 18),
                _StepHeader(2, 'wizGoods'),
                if (_presets.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text(tr(context, 'sdUsual'), style: TextStyle(color: AppColors.muted, fontSize: 12)),
                      for (final (i, p) in _presets.indexed)
                        ActionChip(
                          key: ValueKey('sdPreset_$i'),
                          label: Text('${p.cargo} · ${formatNum(p.weight)} t'),
                          onPressed: () => setState(() {
                            if (cargoTypes.contains(p.cargo)) _cargoType = p.cargo;
                            _weightCtrl.text = formatNum(p.weight);
                            if (VehicleTypeService.byId(p.vehicleType) != null) _vehicleType = p.vehicleType;
                          }),
                        ),
                    ]),
                  ),
                FieldLabel(tr(context, 'cargoType')),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _cargoType,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.inventory_2_outlined)),
                  items: [for (final c in cargoTypes) DropdownMenuItem(value: c, child: Text(c))],
                  onChanged: (v) => setState(() => _cargoType = v ?? _cargoType),
                ),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'weightTons')),
                TextFormField(
                  controller: _weightCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(prefixIcon: const Icon(Icons.scale_outlined), hintText: '${tr(context, 'exampleShort')} 8'),
                  validator: (v) {
                    final n = num.tryParse(v?.trim() ?? '');
                    if (n == null || n <= 0 || n > 100) return tr(context, 'invalidNumber');
                    final info = VehicleTypeService.byId(_vehicleType);
                    if (info != null && !info.fits(n)) return trf(context, 'vtTooHeavy', {'max': formatNum(info.maxTons)});
                    return null;
                  }, inputFormatters: [LengthLimitingTextInputFormatter(100)]),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'vehicleTypeNeeded')),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _vehicleType,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.local_shipping_outlined)),
                  items: vehicleTypeItems(context, keep: _vehicleType),
                  onChanged: (v) {
                    setState(() => _vehicleType = v ?? _vehicleType);
                    _formKey.currentState?.validate();
                  },
                ),
                Builder(builder: (context) {
                  final w = num.tryParse(_weightCtrl.text.trim());
                  final s = SmartDefaults.suggestVehicle(w, VehicleTypeService.types);
                  final current = VehicleTypeService.byId(_vehicleType);
                  // Offer it when the chosen vehicle cannot carry the weight, or a smaller one would do.
                  if (s == null || s.id == _vehicleType || (current != null && current.fits(w!) && current.maxTons <= s.maxTons)) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: ActionChip(
                      key: const ValueKey('sdSuggestVehicle'),
                      avatar: const Icon(Icons.lightbulb_outline_rounded, size: 18),
                      label: Text(trf(context, 'sdSuggest', {'type': vehicleTypeLabel(context, s.id), 'w': formatNum(w!)})),
                      onPressed: () {
                        setState(() => _vehicleType = s.id);
                        _formKey.currentState?.validate();
                      },
                    ),
                  );
                }),
                MatchingVehiclesLine(vehicleType: _vehicleType, weight: num.tryParse(_weightCtrl.text.trim())),
                SwitchListTile(
                  key: const ValueKey('fragileSwitch'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr(context, 'fragileGoods')),
                  value: _fragile,
                  onChanged: (v) => setState(() => _fragile = v),
                ),
                SwitchListTile(
                  key: const ValueKey('highValueSwitch'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr(context, 'highValueGoods')),
                  value: _highValue,
                  onChanged: (v) => setState(() => _highValue = v),
                ),
                const SizedBox(height: 10),
                FieldLabel(tr(context, 'declaredValueLabel')),
                TextFormField(
                  key: const ValueKey('declaredValue'),
                  controller: _valueCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(prefixIcon: const Icon(Icons.currency_rupee_rounded), helperText: tr(context, 'declaredValueHelp'), helperMaxLines: 2),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return null;
                    final n = int.tryParse(t);
                    return (n == null || n * 100 > CancelReasons.maxDeclaredValuePaise) ? tr(context, 'invalidNumber') : null;
                  },
                ),
                const SizedBox(height: 18),
                if (_bookingType == BookingType.rental) ...[
                  FieldLabel(tr(context, 'rentalPackage')),
                  RentalHoursPicker(value: _rentalHours, onChanged: (h) => setState(() => _rentalHours = h)),
                  const SizedBox(height: 18),
                ],
                if (_bookingType == BookingType.movers) ...[
                  MoversSection(
                    items: _itemsCtrl,
                    floor: _floorCtrl,
                    hasLift: _hasLift,
                    packing: _packing,
                    onLift: (v) => setState(() => _hasLift = v),
                    onPacking: (v) => setState(() => _packing = v),
                  ),
                  const SizedBox(height: 18),
                ],
                FieldLabel(tr(context, 'helpersLabel')),
                HelpersStepper(value: _helpers, onChanged: (n) => setState(() => _helpers = n)),
                const SizedBox(height: 18),
                _StepHeader(3, 'wizPrice'),
                FieldLabel(tr(context, 'fareEstimate')),
                _estimateCard(),
                const SizedBox(height: 12),
                OffersSection(total: _quote?.total, onChanged: (c) => setState(() => _offers = c)),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'budgetOptional')),
                TextFormField(
                  controller: _budgetCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.currency_rupee_rounded)),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return null;
                    final n = num.tryParse(t);
                    return (n == null || n <= 0) ? tr(context, 'invalidNumber') : null;
                  }, inputFormatters: [LengthLimitingTextInputFormatter(10)]),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'pickupDate')),
                FormField<DateTime>(
                  validator: (_) => _pickupDate == null ? tr(context, 'fieldRequired') : null,
                  builder: (field) => InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _pickDate(field),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.calendar_today_rounded),
                        errorText: field.errorText,
                      ),
                      child: Text(
                        _pickupDate == null ? '--' : formatDate(_pickupDate),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SwitchListTile(
                  key: const ValueKey('instantSwitch'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr(context, 'instantLabel')),
                  subtitle: Text(tr(context, 'instantSub')),
                  value: _instant,
                  onChanged: (v) => setState(() {
                    _instant = v;
                    if (v) {
                      _pickupDate = DateUtils.dateOnly(DateTime.now());
                      _pickupTime = null;
                    }
                  }),
                ),
                SwitchListTile(
                  key: const ValueKey('scheduleSwitch'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr(context, 'scheduleExactTime')),
                  subtitle: Text(tr(context, 'scheduleExactTimeHint')),
                  value: _pickupTime != null,
                  onChanged: (v) {
                    if (v) {
                      setState(() => _instant = false);
                      _pickTime();
                    } else {
                      setState(() => _pickupTime = null);
                    }
                  },
                ),
                if (_pickupTime != null)
                  OutlinedButton.icon(
                    key: const ValueKey('pickupTimeButton'),
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule_rounded),
                    label: Text(_pickupTime!.format(context)),
                  )
                else ...[
                FieldLabel(tr(context, 'pickupSlot')),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  key: const ValueKey('pickupSlot'),
                  initialValue: _slot,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.schedule_rounded)),
                  items: [for (final x in PickupSlot.all) DropdownMenuItem(value: x, child: Text(pickupSlotLabel(context, x)))],
                  onChanged: (v) => setState(() => _slot = v ?? _slot),
                ),
                ],
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'paymentMode')),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  key: const ValueKey('paymentMode'),
                  initialValue: _paymentMode,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.payments_outlined)),
                  items: [for (final m in PaymentMode.all) DropdownMenuItem(value: m, child: Text(paymentModeLabel(context, m)))],
                  onChanged: (v) => setState(() => _paymentMode = v ?? _paymentMode),
                ),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'visibilityLabel')),
                DropdownButtonFormField<String>(
                  key: const ValueKey('visibility'),
                  isExpanded: true,
                  initialValue: _visibility,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.visibility_outlined)),
                  items: [
                    DropdownMenuItem(value: LoadVisibility.public, child: Text(tr(context, 'visPublic'))),
                    DropdownMenuItem(value: LoadVisibility.favourites, child: Text(tr(context, 'visFavourites'))),
                    if (widget.invitedDriverId != null) DropdownMenuItem(value: LoadVisibility.invite, child: Text(tr(context, 'visInvite'))),
                  ],
                  onChanged: (v) => setState(() => _visibility = v ?? _visibility),
                ),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'repeatLabel')),
                DropdownButtonFormField<String>(
                  key: const ValueKey('repeat'),
                  isExpanded: true,
                  initialValue: _repeat,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.repeat_rounded)),
                  items: [
                    DropdownMenuItem(value: '', child: Text(tr(context, 'repeatNone'))),
                    DropdownMenuItem(value: Frequency.weekly, child: Text(tr(context, 'repeatWeekly'))),
                    DropdownMenuItem(value: Frequency.monthly, child: Text(tr(context, 'repeatMonthly'))),
                  ],
                  onChanged: (v) => setState(() => _repeat = v ?? ''),
                ),
                TradeDetailsSection(
                  container: _containerCtrl,
                  seal: _sealCtrl,
                  branchId: _branchId,
                  onBranch: (b) => setState(() {
                    _branchId = b?.id;
                    if (b != null) _pickupCtrl.text = b.place;
                  }),
                  onHub: (h, {required asPickup}) => setState(() => (asPickup ? _pickupCtrl : _dropCtrl).text = h.place),
                ),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'notesOptional')),
                TextFormField(
                  controller: _notesCtrl,
                  validator: _notesValidator,
                  maxLines: 3,
                  maxLength: 300,
                  decoration: const InputDecoration(),
                ),
                if (_businessId != null) ...[
                  const SizedBox(height: 18),
                  FieldLabel(tr(context, 'costCenterOptional')),
                  TextFormField(
                    key: const ValueKey('costCenter'),
                    controller: _costCenterCtrl,
                    maxLength: 30,
                    decoration: InputDecoration(hintText: tr(context, 'costCenterHint')),
                  ),
                  if (_pool.isNotEmpty)
                    SwitchListTile(
                      key: const ValueKey('poolOnly'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(trf(context, 'bizPoolOnly', {'n': _pool.length})),
                      value: _poolOnly,
                      onChanged: (v) => setState(() => _poolOnly = v),
                    ),
                ],
                const SizedBox(height: 20),
                PrimaryButton(label: tr(context, 'postLoad'), icon: Icons.send_rounded, loading: _saving, onPressed: _submit),
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    key: const ValueKey('saveTemplate'),
                    onPressed: _saveTemplate,
                    icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                    label: Text(tr(context, 'saveAsTemplate')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _TemplateNameDialog extends StatefulWidget {
  const _TemplateNameDialog();

  @override
  State<_TemplateNameDialog> createState() => _TemplateNameDialogState();
}

class _TemplateNameDialogState extends State<_TemplateNameDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(context, 'saveAsTemplate')),
      content: TextField(
        key: const ValueKey('templateName'),
        controller: _name,
        maxLength: 40,
        autofocus: true,
        decoration: InputDecoration(labelText: tr(context, 'templateName')),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr(context, 'cancel'))),
        FilledButton(key: const ValueKey('templateNameOk'), onPressed: () => Navigator.pop(context, _name.text), child: Text(tr(context, 'save'))),
      ],
    );
  }
}


/// "Step 2 of 3" and what the step is about, so the long form reads as three short steps (MASTER-5 Task 31).
class _StepHeader extends StatelessWidget {
  final int step;
  final String titleKey;
  const _StepHeader(this.step, this.titleKey);

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: ValueKey('postStep$step'),
      padding: const EdgeInsets.only(top: 6, bottom: 12),
      child: Row(children: [
        CircleAvatar(radius: 14, backgroundColor: AppColors.primary, child: Text('$step', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(trf(context, 'wizStepOf', {'n': step}), style: TextStyle(fontSize: 12, color: AppColors.muted)),
            Text(tr(context, titleKey), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.title)),
          ]),
        ),
      ]),
    );
  }
}
