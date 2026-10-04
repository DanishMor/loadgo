import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/constants/logistics.dart';
import '../core/services/load_service.dart';
import 'matching_vehicles_line.dart';
import '../core/widgets/common.dart';
import '../core/models/risk.dart';
import '../core/l10n/l10n.dart';
import '../core/services/vehicle_type_service.dart';
import '../core/widgets/logistics_labels.dart';
import '../core/services/pricing_service.dart';
import '../core/pricing/fare_calculator.dart';
import '../core/widgets/fare_breakdown.dart';
import '../core/constants/prohibited_cargo.dart';
import '../core/models/load.dart';
import '../core/widgets/booking_type_widgets.dart';
import 'saved_place_picker.dart';
import '../core/models/ledger_entry.dart';
import '../core/documents/payment_card.dart';
import 'trade_details_section.dart';
import 'offers_section.dart';
import '../core/offers/promo.dart';
import '../core/services/rewards_service.dart';

/// Customer form to post a load. Pops with `true` once posted.
/// [repostFrom] prefills everything except the pickup date.
class PostLoadScreen extends StatefulWidget {
  final Load? repostFrom;

  const PostLoadScreen({super.key, this.repostFrom});

  @override
  State<PostLoadScreen> createState() => _PostLoadScreenState();
}

class _PostLoadScreenState extends State<PostLoadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pickupCtrl = TextEditingController();
  final _dropCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
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
    _pickupCtrl.dispose();
    _dropCtrl.dispose();
    _weightCtrl.dispose();
    _budgetCtrl.dispose();
    _notesCtrl.dispose();
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
        validator: _requiredText,
      ),
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
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            )
          else
            Text(
              auto != null ? trf(context, 'distanceAuto', {'km': auto}) : tr(context, 'distanceUnknown'),
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          if (_bookingType != BookingType.rental) const SizedBox(height: 10),
          if (_bookingType != BookingType.rental) TextFormField(
            key: const ValueKey('distanceKm'),
            controller: _distanceCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
                      Text(tr(context, 'fareTotal'), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                      Text(formatPaise(quote.total),
                          key: const ValueKey('fareTotal'),
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.title)),
                    ],
                  ),
                ),
                TextButton(onPressed: () => showFareBreakdown(context, quote), child: Text(tr(context, 'viewBreakdown'))),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Text(tr(context, 'estimateNote'), style: const TextStyle(color: AppColors.faint, fontSize: 12)),
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
    setState(() => _pickupDate = picked);
    field.didChange(picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final budgetText = _budgetCtrl.text.trim();
      final quote = _quote;
      // Number the promo slot for the final total, and decide the credits.
      PromoApplication? promo;
      var credits = 0;
      if (quote != null) {
        if (_offers.promo != null) promo = await RewardsService.reserve(_offers.promo!.code, quote.total);
        if (_offers.useCredits) {
          credits = creditsToSpend(
              total: quote.total, promo: _offers.promo, creditsBalance: await RewardsService.balance(), useCredits: true);
        }
      }
      await LoadService.post(
        promo: promo,
        creditsUsedPaise: credits,
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
      showSnack(context, tr(context, 'loadPosted'));
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
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  String? _requiredText(String? v) => (v == null || v.trim().length < 2) ? tr(context, 'fieldRequired') : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                FieldLabel(tr(context, 'bookingTypeLabel')),
                BookingTypePicker(value: _bookingType, onChanged: (t) => setState(() => _bookingType = t)),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'pickupLocation')),
                TextFormField(
                  controller: _pickupCtrl,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.trip_origin_rounded, color: AppColors.success),
                    suffixIcon: _savedPlaceButton(_pickupCtrl),
                  ),
                  validator: _requiredText,
                ),
                for (final (i, c) in _extraPickups.indexed)
                  _stopField(c, trf(context, 'pickupStopN', {'n': i + 2}), _extraPickups, pickup: true),
                _addStopButton(_extraPickups, 'addPickupStop', 'addPickupStop'),
                const SizedBox(height: 8),
                FieldLabel(tr(context, 'dropLocation')),
                for (final (i, c) in _extraDrops.indexed)
                  _stopField(c, trf(context, 'dropStopN', {'n': i + 1}), _extraDrops, pickup: false),
                if (_extraDrops.isNotEmpty) const SizedBox(height: 10),
                TextFormField(
                  controller: _dropCtrl,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.location_on_rounded, color: Colors.redAccent),
                    suffixIcon: _savedPlaceButton(_dropCtrl),
                  ),
                  validator: (v) => _bookingType == BookingType.rental ? null : _requiredText(v),
                ),
                _addStopButton(_extraDrops, 'addDropStop', 'addDropStop'),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'cargoType')),
                DropdownButtonFormField<String>(
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
                  },
                ),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'vehicleTypeNeeded')),
                DropdownButtonFormField<String>(
                  initialValue: _vehicleType,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.local_shipping_outlined)),
                  items: vehicleTypeItems(context, keep: _vehicleType),
                  onChanged: (v) {
                    setState(() => _vehicleType = v ?? _vehicleType);
                    _formKey.currentState?.validate();
                  },
                ),
                MatchingVehiclesLine(vehicleType: _vehicleType, weight: num.tryParse(_weightCtrl.text.trim())),
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
                  },
                ),
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
                FieldLabel(tr(context, 'pickupSlot')),
                DropdownButtonFormField<String>(
                  key: const ValueKey('pickupSlot'),
                  initialValue: _slot,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.schedule_rounded)),
                  items: [for (final x in PickupSlot.all) DropdownMenuItem(value: x, child: Text(pickupSlotLabel(context, x)))],
                  onChanged: (v) => setState(() => _slot = v ?? _slot),
                ),
                const SizedBox(height: 18),
                FieldLabel(tr(context, 'paymentMode')),
                DropdownButtonFormField<String>(
                  key: const ValueKey('paymentMode'),
                  initialValue: _paymentMode,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.payments_outlined)),
                  items: [for (final m in PaymentMode.all) DropdownMenuItem(value: m, child: Text(paymentModeLabel(context, m)))],
                  onChanged: (v) => setState(() => _paymentMode = v ?? _paymentMode),
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
                const SizedBox(height: 20),
                PrimaryButton(label: tr(context, 'postLoad'), icon: Icons.send_rounded, loading: _saving, onPressed: _submit),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
