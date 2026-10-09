import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../pricing/cancel_preview.dart';
import '../pricing/fare_calculator.dart';
import '../services/pricing_service.dart';
import '../pricing/surge.dart';
import 'common.dart';

/// String key of the surge line for a `SurgeKind`.
String surgeLabelKey(String kind) => switch (kind) {
      SurgeKind.night => 'fareSurgeNight',
      SurgeKind.festival => 'fareSurgeFestival',
      _ => 'fareSurgePeak',
    };

/// Line-by-line fare breakdown (all paise). Zero lines are skipped. With
/// [explain] every line has a "What is this?" tap that opens one plain sentence.
class FareBreakdownView extends StatefulWidget {
  final FareBreakdown fare;
  final bool explain;
  const FareBreakdownView({super.key, required this.fare, this.explain = false});

  @override
  State<FareBreakdownView> createState() => _FareBreakdownViewState();
}

class _FareBreakdownViewState extends State<FareBreakdownView> {
  final Set<String> _open = {};

  Widget _row(String label, int paise, {bool bold = false, String? why}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(color: bold ? AppColors.title : AppColors.muted, fontWeight: bold ? FontWeight.w800 : null)),
              ),
              if (widget.explain && why != null)
                InkWell(
                  key: ValueKey('fexInfo_$why'),
                  onTap: () => setState(() => _open.contains(why) ? _open.remove(why) : _open.add(why)),
                  customBorder: const CircleBorder(),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Icon(Icons.help_outline_rounded, size: 18, semanticLabel: tr(context, 'fexWhat'), color: AppColors.faint),
                  ),
                ),
              Text(formatPaise(paise),
                  style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: AppColors.title)),
            ],
          ),
          if (widget.explain && why != null && _open.contains(why))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(tr(context, why), key: ValueKey('fexText_$why'), style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final f = widget.fare;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (f.rentalCharge > 0)
          _row(tr(context, 'fareRental'), f.rentalCharge, why: 'fexBase')
        else ...[
          _row(tr(context, 'fareBase'), f.baseFare, why: 'fexBase'),
          _row(trf(context, 'fareDistance', {'km': f.distanceKm}), f.distanceCharge, why: 'fexDistance'),
        ],
        if (f.extraKmCharge > 0) _row(tr(context, 'fareExtraKm'), f.extraKmCharge, why: 'fexDistance'),
        if (f.extraHourCharge > 0) _row(tr(context, 'fareExtraHours'), f.extraHourCharge, why: 'fexWaiting'),
        if (f.helperCharge > 0) _row(tr(context, 'fareHelpers'), f.helperCharge, why: 'fexHelpers'),
        if (f.itemHandlingCharge > 0) _row(tr(context, 'fareItemHandling'), f.itemHandlingCharge, why: 'fexHandling'),
        if (f.floorCharge > 0) _row(tr(context, 'fareFloors'), f.floorCharge, why: 'fexHandling'),
        if (f.packingCharge > 0) _row(tr(context, 'farePacking'), f.packingCharge, why: 'fexHandling'),
        if (f.loadingCharge > 0) _row(tr(context, 'fareLoading'), f.loadingCharge, why: 'fexHandling'),
        if (f.unloadingCharge > 0) _row(tr(context, 'fareUnloading'), f.unloadingCharge, why: 'fexHandling'),
        if (f.waitingCharge > 0) _row(tr(context, 'fareWaiting'), f.waitingCharge, why: 'fexWaiting'),
        if (f.extraStopCharge > 0) _row(tr(context, 'fareExtraStops'), f.extraStopCharge, why: 'fexStops'),
        if (f.minimumFareAdjustment > 0) _row(tr(context, 'fareMinimum'), f.minimumFareAdjustment, why: 'fexMinimum'),
        if (f.surgeCharge > 0) _row(trf(context, surgeLabelKey(f.surgeKind), {'p': f.surgePercent}), f.surgeCharge, why: 'fexSurge'),
        const Divider(),
        _row(tr(context, 'fareTrip'), f.tripFare, bold: true),
        _row(trf(context, 'farePlatform', {'p': formatNum(f.platformFeePercent)}), f.platformFee, why: 'fexPlatform'),
        _row(trf(context, 'fareGst', {'p': formatNum(f.gstPercent)}), f.gst, why: 'fexGst'),
        const Divider(),
        _row(tr(context, 'fareTotal'), f.total, bold: true),
      ],
    );
  }
}

/// "If you cancel" in four plain lines, from the live cancellation policy.
class CancelPreviewView extends StatelessWidget {
  final CancelPreview preview;
  const CancelPreviewView({super.key, required this.preview});

  @override
  Widget build(BuildContext context) {
    final p = preview;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr(context, 'fexCancelTitle'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Text(tr(context, 'fexCancelOpen'), key: const ValueKey('fexCancelOpen')),
      Text(trf(context, 'fexCancelFree', {'m': p.freeMinutes}), key: const ValueKey('fexCancelFree')),
      Text(trf(context, 'fexCancelAfter', {'amount': formatPaise(p.chargePaise), 'p': formatNum(p.chargePercent), 'min': formatPaise(p.minCharge), 'max': formatPaise(p.maxCharge)}), key: const ValueKey('fexCancelAfter')),
      Text(trf(context, 'fexCancelScheduled', {'h': p.scheduledFreeHours}), key: const ValueKey('fexCancelScheduled')),
      const SizedBox(height: 4),
      Text(tr(context, 'fexCancelNote'), style: TextStyle(color: AppColors.muted, fontSize: 12)),
    ]);
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
              FareBreakdownView(fare: fare, explain: true),
              const SizedBox(height: 14),
              CancelPreviewView(preview: CancelPreview.of(PricingService.config.cancellation, farePaise: fare.total)),
              const SizedBox(height: 10),
              Text(tr(c, 'estimateNote'), style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
