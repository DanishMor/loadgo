import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/logistics.dart';
import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../models/trip_evidence.dart';
import '../services/trip_evidence_service.dart';
import 'common.dart';
import 'signature_pad.dart';

String cargoDocLabel(BuildContext context, String type) => tr(context, 'cargoDoc_$type');

/// Driver: odometer at the start and end of the trip (km, once each) and the
/// receiver signature at delivery.
class DriverEvidenceCard extends StatefulWidget {
  final Booking booking;
  const DriverEvidenceCard({super.key, required this.booking});

  @override
  State<DriverEvidenceCard> createState() => _DriverEvidenceCardState();
}

class _DriverEvidenceCardState extends State<DriverEvidenceCard> {
  final _km = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _km.dispose();
    super.dispose();
  }

  Booking get _b => widget.booking;

  bool get _canStart => _b.odometerStart == null && const [BookingStatus.accepted, BookingStatus.driverArriving, BookingStatus.loading, BookingStatus.pickedUp].contains(_b.status);
  bool get _canEnd => _b.odometerEnd == null && const [BookingStatus.inTransit, BookingStatus.unloading, BookingStatus.delivered].contains(_b.status);
  bool get _canSign => const [BookingStatus.unloading, BookingStatus.delivered].contains(_b.status);

  Future<void> _saveOdometer({required bool start}) async {
    final km = int.tryParse(_km.text.trim());
    if (km == null) return showSnack(context, tr(context, 'invalidNumber'));
    setState(() => _busy = true);
    try {
      await TripEvidenceService.setOdometer(_b, start: start, km: km);
      _km.clear();
      if (mounted) showSnack(context, tr(context, 'settingsSaved'));
    } on EvidenceException catch (e) {
      if (mounted) showSnack(context, tr(context, e.reason == 'end_before_start' ? 'odometerEndBeforeStart' : 'invalidNumber'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sign() async {
    final sig = await showSignatureDialog(context);
    if (sig == null || !mounted) return;
    try {
      await TripEvidenceService.saveSignature(_b, sig);
      if (mounted) showSnack(context, tr(context, 'signatureSaved'));
    } on EvidenceException catch (e) {
      if (mounted) showSnack(context, tr(context, e.reason == 'already' ? 'signatureAlready' : 'somethingWrong'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_canStart && !_canEnd && !_canSign && _b.odometerStart == null) return const SizedBox.shrink();
    return AppCard(
      key: const ValueKey('evidenceCard'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(context, 'tripEvidence'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 6),
        if (_b.odometerStart != null) Text(trf(context, 'odometerStartIs', {'km': _b.odometerStart!}), key: const ValueKey('odoStart')),
        if (_b.odometerEnd != null) Text(trf(context, 'odometerEndIs', {'km': _b.odometerEnd!}), key: const ValueKey('odoEnd')),
        if (_b.odometerStart != null && _b.odometerEnd != null)
          Text(trf(context, 'odometerDistance', {'km': _b.odometerEnd! - _b.odometerStart!}), key: const ValueKey('odoDistance'), style: const TextStyle(fontWeight: FontWeight.w700)),
        if (_canStart || _canEnd)
          Row(children: [
            Expanded(
              child: TextField(
                key: const ValueKey('odoField'),
                controller: _km,
                keyboardType: TextInputType.number,
                inputFormatters: [LengthLimitingTextInputFormatter(10), FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: tr(context, 'odometerKm')),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              key: const ValueKey('odoSave'),
              onPressed: _busy ? null : () => _saveOdometer(start: _canStart),
              child: Text(tr(context, _canStart ? 'odometerSaveStart' : 'odometerSaveEnd')),
            ),
          ]),
        if (_canSign)
          StreamBuilder<SignatureStrokes?>(
            stream: TripEvidenceService.watchSignature(_b.id),
            builder: (context, snap) => snap.data != null
                ? Padding(padding: const EdgeInsets.only(top: 8), child: SignatureView(signature: snap.data!))
                : Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(
                      key: const ValueKey('signReceiver'),
                      onPressed: _sign,
                      icon: const Icon(Icons.draw_outlined),
                      label: Text(tr(context, 'receiverSignature')),
                    ),
                  ),
          ),
      ]),
    );
  }
}

/// Cargo document records for a booking, with their history. Either party
/// can add; nothing is overwritten.
class CargoDocsCard extends StatefulWidget {
  final Booking booking;
  const CargoDocsCard({super.key, required this.booking});

  @override
  State<CargoDocsCard> createState() => _CargoDocsCardState();
}

class _CargoDocsCardState extends State<CargoDocsCard> {
  late final Stream<List<CargoDoc>> _docs = TripEvidenceService.watchCargoDocs(widget.booking.id).asBroadcastStream();
  String _type = CargoDocType.invoice;
  final _number = TextEditingController();
  final _note = TextEditingController();
  int? _leg;

  @override
  void dispose() {
    _number.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    try {
      await TripEvidenceService.addCargoDoc(widget.booking, type: _type, number: _number.text, note: _note.text, leg: _leg);
      _number.clear();
      _note.clear();
      if (mounted) showSnack(context, tr(context, 'settingsSaved'));
    } on EvidenceException {
      if (mounted) showSnack(context, tr(context, 'cargoDocInvalid'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final twoLeg = widget.booking.route.length > 2; // legs only matter for multi-stop / two-leg
    return AppCard(
      key: const ValueKey('cargoDocsCard'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(context, 'cargoDocsTitle'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        StreamBuilder<List<CargoDoc>>(
          stream: _docs,
          builder: (context, snap) {
            final all = snap.data ?? const <CargoDoc>[];
            final latest = CargoDoc.latestByType(all);
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final d in latest.values)
                Padding(
                  key: ValueKey('cargoDoc_${d.type}_${d.leg ?? 0}'),
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${cargoDocLabel(context, d.type)}${d.leg == null ? '' : ' (${trf(context, 'legN', {'n': d.leg!})})'}: ${d.number}'
                    '${all.where((x) => x.type == d.type && x.leg == d.leg).length > 1 ? ' · ${trf(context, 'cargoDocVersions', {'n': all.where((x) => x.type == d.type && x.leg == d.leg).length})}' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
            ]);
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          isExpanded: true,
          key: const ValueKey('cargoDocType'),
          initialValue: _type,
          items: [for (final t in CargoDocType.all) DropdownMenuItem(value: t, child: Text(cargoDocLabel(context, t)))],
          onChanged: (v) => setState(() => _type = v ?? _type),
        ),
        TextField(key: const ValueKey('cargoDocNumber'), controller: _number, maxLength: 40, decoration: InputDecoration(labelText: tr(context, 'docNumber'))),
        TextField(key: const ValueKey('cargoDocNote'), controller: _note, maxLength: 200, decoration: InputDecoration(labelText: tr(context, 'noteOptional'))),
        if (twoLeg)
          Wrap(spacing: 8, children: [
            for (final l in const [null, 1, 2])
              ChoiceChip(label: Text(l == null ? tr(context, 'all') : trf(context, 'legN', {'n': l})), selected: _leg == l, onSelected: (_) => setState(() => _leg = l)),
          ]),
        FilledButton.tonal(key: const ValueKey('cargoDocAdd'), onPressed: _add, child: Text(tr(context, 'cargoDocAdd'))),
        const SizedBox(height: 4),
        Text(tr(context, 'cargoDocsNote'), style: TextStyle(color: AppColors.faint, fontSize: 12)),
      ]),
    );
  }
}
