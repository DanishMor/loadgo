import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/fleet/fleet_logic.dart';
import '../core/models/booking.dart';
import '../core/models/vehicle.dart';
import '../core/services/booking_service.dart';
import '../core/services/vehicle_service.dart';
import '../core/safety/call.dart';
import '../core/services/safety_service.dart';
import '../core/services/trip_evidence_service.dart';
import '../core/services/user_service.dart';
import '../core/widgets/common.dart';

/// SOS and breakdown actions on the driver's active trip.
class TripSafetyCard extends StatefulWidget {
  final Booking booking;
  const TripSafetyCard({super.key, required this.booking});

  @override
  State<TripSafetyCard> createState() => _TripSafetyCardState();
}

class _TripSafetyCardState extends State<TripSafetyCard> {
  bool _busy = false;

  Future<void> _sos() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr(c, 'sos')),
        content: Text(tr(c, 'sosConfirm')),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: Text(tr(c, 'cancel'))),
          FilledButton(
            key: const ValueKey('sosConfirm'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(c).pop(true),
            child: Text(tr(c, 'sos')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    List<EmergencyContact> contacts = const [];
    try {
      await SafetyService.sendSos(booking: widget.booking);
      contacts = SafetyService.contactsFrom(await UserService.getUser());
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(tr(c, 'sosSent')),
        actions: [
          for (final ct in contacts) TextButton(onPressed: () => callNumber(c, ct.phone), child: Text(ct.name)),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => callNumber(c, '112'),
            icon: const Icon(Icons.call_rounded),
            label: Text(tr(c, 'call112')),
          ),
        ],
      ),
    );
  }

  /// After a breakdown with a replacement requested: pick another vehicle of
  /// the driver's that is free and can carry the load, and move the trip to it.
  Future<void> _switchVehicle() async {
    setState(() => _busy = true);
    try {
      final all = await VehicleService.fetchMyActive();
      final options = replacementCandidates(all, weight: widget.booking.weight, preferType: widget.booking.vehicleType, excludeId: widget.booking.vehicleId);
      if (!mounted) return;
      if (options.isEmpty) return showSnack(context, tr(context, 'switchNone'));
      final pick = await showDialog<Vehicle>(
        context: context,
        builder: (c) => SimpleDialog(
          title: Text(tr(c, 'switchVehicleTitle')),
          children: [
            for (final v in options)
              ListTile(key: ValueKey('switchTo_${v.id}'), leading: const Icon(Icons.local_shipping_rounded), title: Text(v.number), subtitle: Text('${v.type} · ${formatNum(v.capacity)} T'), onTap: () => Navigator.pop(c, v)),
          ],
        ),
      );
      if (pick == null || !mounted) return;
      Vehicle? old;
      for (final v in all) {
        if (v.id == widget.booking.vehicleId) old = v;
      }
      await BookingService.replaceVehicle(widget.booking, pick, old: old);
      if (mounted) showSnack(context, tr(context, 'vehicleSwitched'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _breakdown() async {
    final result = await showDialog<(String, bool)>(context: context, builder: (_) => const _BreakdownDialog());
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await SafetyService.reportBreakdown(widget.booking, note: result.$1, needReplacement: result.$2);
      if (mounted) showSnack(context, tr(context, 'breakdownReported'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accident() async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr(c, 'reportAccident')),
        content: TextField(key: const ValueKey('accidentText'), controller: ctrl, maxLength: 500, maxLines: 3, decoration: InputDecoration(labelText: tr(c, 'accidentDescribe'))),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(), child: Text(tr(c, 'cancel'))),
          FilledButton(key: const ValueKey('accidentSubmit'), onPressed: () => Navigator.of(c).pop(ctrl.text), child: Text(tr(c, 'reportAccident'))),
        ],
      ),
    );
    if (text == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await TripEvidenceService.reportAccident(widget.booking, text);
      if (mounted) showSnack(context, tr(context, 'accidentReported'));
    } on EvidenceException {
      if (mounted) showSnack(context, tr(context, 'accidentTooShort'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _buttons(),
      if (widget.booking.breakdown?.replacementRequested == true && widget.booking.isActive)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('switchVehicleButton'),
            onPressed: _busy ? null : _switchVehicle,
            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
            label: Text(tr(context, 'switchVehicle')),
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('accidentButton'),
          onPressed: _busy ? null : _accident,
          icon: const Icon(Icons.warning_amber_rounded, size: 18),
          label: Text(tr(context, 'reportAccident')),
        ),
      ),
    ]);
  }

  Widget _buttons() {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            key: const ValueKey('sosButton'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red, minimumSize: const Size.fromHeight(46)),
            onPressed: _busy ? null : _sos,
            icon: const Icon(Icons.sos_rounded),
            label: Text(tr(context, 'sos')),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            key: const ValueKey('breakdownButton'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            onPressed: _busy || widget.booking.breakdown != null ? null : _breakdown,
            icon: const Icon(Icons.car_crash_outlined),
            label: Text(tr(context, 'reportBreakdown'), overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
    );
  }
}

class _BreakdownDialog extends StatefulWidget {
  const _BreakdownDialog();

  @override
  State<_BreakdownDialog> createState() => _BreakdownDialogState();
}

class _BreakdownDialogState extends State<_BreakdownDialog> {
  final _note = TextEditingController();
  bool _replacement = true;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(context, 'reportBreakdown')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _note,
            maxLength: 300,
            maxLines: 2,
            decoration: InputDecoration(labelText: tr(context, 'breakdownNote'), counterText: ''),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _replacement,
            onChanged: (v) => setState(() => _replacement = v ?? true),
            title: Text(tr(context, 'needReplacement')),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr(context, 'cancel'))),
        FilledButton(
          key: const ValueKey('breakdownSubmit'),
          onPressed: () => Navigator.of(context).pop((_note.text, _replacement)),
          child: Text(tr(context, 'reportBreakdown')),
        ),
      ],
    );
  }
}
