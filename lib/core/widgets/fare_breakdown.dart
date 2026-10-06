import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../pricing/fare_calculator.dart';
import 'common.dart';

/// Line-by-line fare breakdown (all paise). Zero lines are skipped.
class FareBreakdownView extends StatelessWidget {
  final FareBreakdown fare;
  const FareBreakdownView({super.key, required this.fare});

  Widget _row(String label, int paise, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(color: bold ? AppColors.title : AppColors.muted, fontWeight: bold ? FontWeight.w800 : null)),
            ),
            Text(formatPaise(paise),
                style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: AppColors.title)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final f = fare;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (f.rentalCharge > 0)
          _row(tr(context, 'fareRental'), f.rentalCharge)
        else ...[
          _row(tr(context, 'fareBase'), f.baseFare),
          _row(trf(context, 'fareDistance', {'km': f.distanceKm}), f.distanceCharge),
        ],
        if (f.extraKmCharge > 0) _row(tr(context, 'fareExtraKm'), f.extraKmCharge),
        if (f.extraHourCharge > 0) _row(tr(context, 'fareExtraHours'), f.extraHourCharge),
        if (f.helperCharge > 0) _row(tr(context, 'fareHelpers'), f.helperCharge),
        if (f.itemHandlingCharge > 0) _row(tr(context, 'fareItemHandling'), f.itemHandlingCharge),
        if (f.floorCharge > 0) _row(tr(context, 'fareFloors'), f.floorCharge),
        if (f.packingCharge > 0) _row(tr(context, 'farePacking'), f.packingCharge),
        if (f.loadingCharge > 0) _row(tr(context, 'fareLoading'), f.loadingCharge),
        if (f.unloadingCharge > 0) _row(tr(context, 'fareUnloading'), f.unloadingCharge),
        if (f.waitingCharge > 0) _row(tr(context, 'fareWaiting'), f.waitingCharge),
        if (f.extraStopCharge > 0) _row(tr(context, 'fareExtraStops'), f.extraStopCharge),
        if (f.minimumFareAdjustment > 0) _row(tr(context, 'fareMinimum'), f.minimumFareAdjustment),
        const Divider(),
        _row(tr(context, 'fareTrip'), f.tripFare, bold: true),
        _row(trf(context, 'farePlatform', {'p': formatNum(f.platformFeePercent)}), f.platformFee),
        _row(trf(context, 'fareGst', {'p': formatNum(f.gstPercent)}), f.gst),
        const Divider(),
        _row(tr(context, 'fareTotal'), f.total, bold: true),
      ],
    );
  }
}

/// Bottom sheet with [FareBreakdownView] and the estimate disclaimer.
Future<void> showFareBreakdown(BuildContext context, FareBreakdown fare) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr(c, 'fareEstimate'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              FareBreakdownView(fare: fare),
              const SizedBox(height: 10),
              Text(tr(c, 'estimateNote'), style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
