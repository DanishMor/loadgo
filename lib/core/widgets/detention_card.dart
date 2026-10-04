import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../pricing/fare_calculator.dart';
import '../services/booking_service.dart';
import '../services/pricing_service.dart';
import '../services/vehicle_type_service.dart';
import 'common.dart';

/// Waiting time at loading / unloading with the charge it would cost
/// (record only). The driver gets Start / Stop while the trip is in that
/// stage; the customer sees the same figures. Hidden when there is nothing
/// to show.
class DetentionCard extends StatefulWidget {
  final Booking booking;
  final bool isDriver;

  /// Injectable clock for tests.
  final DateTime Function() now;

  const DetentionCard({super.key, required this.booking, required this.isDriver, this.now = DateTime.now});

  @override
  State<DetentionCard> createState() => _DetentionCardState();
}

class _DetentionCardState extends State<DetentionCard> {
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Keep the running minutes fresh while the clock is on.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _running) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _stage => widget.booking.status;
  bool get _inStage => _stage == Detention.loadingStage || _stage == Detention.unloadingStage;
  bool get _running => widget.booking.detention.startedAt(_stage) != null;

  int get _charge {
    final b = widget.booking;
    final category = VehicleTypeService.byId(b.vehicleType)?.category ?? 'lcv';
    final cfg = PricingService.config;
    return FareCalculator.detentionCharge(cfg.ruleFor(b.vehicleType, category), b.detention.minutesAt(widget.now()), freeMinutes: cfg.detentionFreeMinutes);
  }

  Future<void> _toggle() async {
    setState(() => _busy = true);
    try {
      if (_running) {
        await BookingService.stopWaiting(widget.booking, now: widget.now());
      } else {
        await BookingService.startWaiting(widget.booking);
      }
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.booking.detention;
    final canControl = widget.isDriver && _inStage;
    if (d.isEmpty && !canControl) return const SizedBox.shrink();
    final minutes = d.minutesAt(widget.now());
    final cfg = PricingService.config;
    return AppCard(
      key: const ValueKey('detentionCard'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.hourglass_bottom_rounded, color: AppColors.warning),
          const SizedBox(width: 8),
          Text(tr(context, 'detentionTitle'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
        const SizedBox(height: 8),
        Text(trf(context, 'detentionMinutes', {'n': minutes}), key: const ValueKey('detentionMinutes'), style: const TextStyle(fontWeight: FontWeight.w700)),
        Text(trf(context, 'detentionCharge', {'amount': formatPaise(_charge), 'free': cfg.detentionFreeMinutes}),
            key: const ValueKey('detentionCharge'), style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        if (canControl)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton.tonal(
              key: const ValueKey('detentionToggle'),
              onPressed: _busy ? null : _toggle,
              child: Text(tr(context, _running ? 'detentionStop' : 'detentionStart')),
            ),
          ),
        const SizedBox(height: 4),
        Text(tr(context, 'detentionNote'), style: const TextStyle(color: AppColors.faint, fontSize: 12)),
      ]),
    );
  }
}
