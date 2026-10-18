import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dispatch_models.dart';
import '../l10n/l10n.dart';
import '../models/load.dart';
import '../models/offer.dart';
import '../models/risk.dart';
import '../services/rate_limit_service.dart';
import '../models/vehicle.dart';
import '../pricing/offer_bounds.dart';
import '../services/offer_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/common.dart';
import '../widgets/ds/app_button.dart';
import '../widgets/ds/app_dialogs.dart';
import '../widgets/ds/fare_meter.dart';
import '../widgets/ds/sheet_kit.dart';
import '../errors/error_text.dart';

/// The numbers behind the driver's bid sheet (U29). Pure, so every rule can be tested without a screen.
class BidSheetModel {
  /// The customer's price in paise, else the fare estimate; 0 when the load has neither.
  final int farePaise;

  /// The fare estimate in paise (what the 30% to 300% rule is measured against); null without one.
  final int? estimatePaise;

  const BidSheetModel({required this.farePaise, required this.estimatePaise});

  factory BidSheetModel.of(Load load) {
    final est = load.estimate?.total;
    final budget = load.budget == null ? 0 : (load.budget! * 100).round();
    return BidSheetModel(farePaise: budget > 0 ? budget : (est ?? 0), estimatePaise: est != null && est > 0 ? est : null);
  }

  static const stepPaise = 1000;
  static const percents = [-5, 5, 10];
  static const etaChoices = [15, 30, 60, 120];

  /// [percent] more or less than the fare, rounded to ten rupees, and never outside what the rules allow.
  int priceAt(int percent) => clamp((((farePaise * (100 + percent)) ~/ 100 + stepPaise ~/ 2) ~/ stepPaise) * stepPaise);

  int get lowest => estimatePaise == null ? stepPaise : OfferBounds.minPaise(estimatePaise!);
  int get highest => estimatePaise == null ? OfferService.maxPaise : OfferBounds.maxPaise(estimatePaise!);

  int clamp(int paise) => paise < lowest ? lowest : (paise > highest ? highest : paise);

  /// null when the price may be sent, else 'low' or 'high'.
  String? check(int paise) {
    if (!OfferService.validPrice(paise)) return 'low';
    return OfferBounds.check(paise, estimatePaise);
  }
}

/// Opens the bid sheet: a new price for [load] with [vehicle], or with [existing] the one allowed change (and a
/// withdraw). Returns true when something was sent, changed or withdrawn.
Future<bool> showDriverBidSheet(BuildContext context, {required Load load, required Vehicle vehicle, int? pickupKm, Offer? existing, bool asCompany = false}) async {
  final r = await showAppSheet<bool>(
    context,
    title: tr(context, 'bsTitle'),
    builder: (_) => DriverBidSheet(load: load, vehicle: vehicle, pickupKm: pickupKm, existing: existing, asCompany: asCompany),
  );
  return r == true;
}

class DriverBidSheet extends StatefulWidget {
  final Load load;
  final Vehicle vehicle;
  final int? pickupKm;
  final Offer? existing;

  /// U35: a transporter bids for the company (the offer carries the company name and the Verified mark).
  final bool asCompany;

  const DriverBidSheet({super.key, required this.load, required this.vehicle, this.pickupKm, this.existing, this.asCompany = false});

  @override
  State<DriverBidSheet> createState() => _DriverBidSheetState();
}

class _DriverBidSheetState extends State<DriverBidSheet> {
  late final BidSheetModel _m = BidSheetModel.of(widget.load);
  late int _price = widget.existing?.pricePaise ?? (_m.farePaise > 0 ? _m.clamp(_m.farePaise) : 0);
  late final TextEditingController _custom = TextEditingController();
  late int? _eta = widget.existing?.etaMinutes;
  late BidNote? _note = widget.existing?.note;
  bool _busy = false;

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  bool get _editing => widget.existing != null;

  /// A bid that was already changed once is locked; the driver can only withdraw it.
  bool get _locked => _editing && widget.existing!.edited;

  String _error(Object e) {
    if (e is OfferOutOfRangeException) return trf(context, 'bsOutOfRange', {'lo': formatPaise(e.minPaise), 'hi': formatPaise(e.maxPaise)});
    if (e is BidWindowClosedException) return tr(context, 'brWindowClosed');
    if (e is OfferExistsException) return tr(context, 'bsAlready');
    if (e is BidAlreadyEditedException) return tr(context, 'bsEditOnce');
    if (e is OfferStateException) return tr(context, 'loadUnavailable');
    if (e is AccountRestrictedException) return tr(context, 'accountRestricted');
    if (e is RateLimitException) return trf(context, 'rateLimited', {'m': e.minutesLeft});
    return errorText(context, e);
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showSnack(context, _error(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() {
    final problem = _m.check(_price);
    if (problem != null) {
      showSnack(context, trf(context, 'bsOutOfRange', {'lo': formatPaise(_m.lowest), 'hi': formatPaise(_m.highest)}));
      return Future.value();
    }
    return _run(() async {
      if (_editing) {
        await OfferService.edit(widget.existing!, pricePaise: _price, etaMinutes: _eta, note: _note, pickupKm: widget.pickupKm ?? widget.existing!.pickupKm);
      } else {
        await OfferService.send(load: widget.load, vehicle: widget.vehicle, pricePaise: _price, etaMinutes: _eta, note: _note, pickupKm: widget.pickupKm, asCompany: widget.asCompany);
      }
    });
  }

  Future<void> _withdraw() async {
    final ok = await showConfirmDialog(context, title: tr(context, 'bsWithdraw'), danger: true);
    if (!ok || !mounted) return;
    await _run(() => OfferService.withdraw(widget.existing!.id));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final est = _m.estimatePaise;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(formatPaise(_price), key: const ValueKey('bsPrice'), textAlign: TextAlign.center, style: DsType.headline.copyWith(color: c.textStrong)),
      if (est != null) ...[
        const SizedBox(height: DsSpace.s1),
        Text(trf(context, 'bsUsual', {'lo': formatPaise(_m.lowest), 'hi': formatPaise(_m.highest)}), textAlign: TextAlign.center, style: DsType.bodySmall.copyWith(color: c.textMuted)),
      ],
      const SizedBox(height: DsSpace.s3),
      if (!_locked) ...[
        if (_m.farePaise > 0) ...[
          Wrap(alignment: WrapAlignment.center, spacing: DsSpace.s2, runSpacing: DsSpace.s2, children: [
            for (final p in BidSheetModel.percents)
              ActionChip(
                key: ValueKey('bsPct_$p'),
                label: Text(p > 0 ? '+$p%' : '$p%'),
                onPressed: () => setState(() {
                  _price = _m.priceAt(p);
                  _custom.clear();
                }),
              ),
          ]),
          const SizedBox(height: DsSpace.s3),
        ],
        TextField(
          key: const ValueKey('bsCustom'),
          controller: _custom,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
          decoration: InputDecoration(labelText: tr(context, 'bsCustom'), prefixText: '₹ '),
          onChanged: (v) => setState(() => _price = (int.tryParse(v) ?? 0) * 100),
        ),
        const SizedBox(height: DsSpace.s3),
        if (est != null)
          FareMeter(
            estimatePaise: est,
            valuePaise: _price.clamp(_m.lowest, _m.highest),
            onChanged: (v) => setState(() => _price = _m.clamp(v)),
          ),
        const SizedBox(height: DsSpace.s3),
        Text(tr(context, 'bsEtaQ'), style: DsType.label.copyWith(color: c.textMuted)),
        QuickChipRow<int>(
          padding: EdgeInsets.zero,
          options: [for (final m in BidSheetModel.etaChoices) (m, trf(context, 'uxEtaMin', {'n': m}))],
          selected: _eta,
          clearable: true,
          onChanged: (v) => setState(() => _eta = v),
        ),
        const SizedBox(height: DsSpace.s2),
        Text(tr(context, 'bsNoteQ'), style: DsType.label.copyWith(color: c.textMuted)),
        QuickChipRow<BidNote>(
          padding: EdgeInsets.zero,
          options: [for (final n in BidNote.values) (n, tr(context, 'bnote_${n.value}'))],
          selected: _note,
          clearable: true,
          onChanged: (v) => setState(() => _note = v),
        ),
        const SizedBox(height: DsSpace.s4),
        AppButton(key: const ValueKey('bsSend'), label: tr(context, _editing ? 'bsEdit' : 'bsSend'), big: true, loading: _busy, onPressed: _busy ? null : _send),
        if (_editing) Padding(padding: const EdgeInsets.only(top: DsSpace.s2), child: Text(tr(context, 'bsEditOnce'), textAlign: TextAlign.center, style: DsType.caption.copyWith(color: c.textMuted))),
      ] else
        Text(tr(context, 'bsEditOnce'), key: const ValueKey('bsLocked'), textAlign: TextAlign.center, style: DsType.body.copyWith(color: c.textMuted)),
      if (_editing) ...[
        const SizedBox(height: DsSpace.s2),
        AppButton(key: const ValueKey('bsWithdraw'), label: tr(context, 'bsWithdraw'), kind: AppButtonKind.danger, onPressed: _busy ? null : _withdraw),
      ],
    ]);
  }
}
