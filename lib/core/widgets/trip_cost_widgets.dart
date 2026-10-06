import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../pricing/trip_cost.dart';
import '../services/pricing_service.dart';
import '../services/vehicle_type_service.dart';
import 'common.dart';

/// Builds the preview for a route and vehicle type with the admin diesel price.
TripCostPreview tripCostFor({required int farePaise, required int km, required String vehicleType, required String from, required String to}) {
  final category = VehicleTypeService.byId(vehicleType)?.category ?? 'lcv';
  return TripCostPreview.compute(
    farePaise: farePaise,
    km: km,
    category: category,
    from: from,
    to: to,
    dieselPaisePerLitre: PricingService.config.dieselPaisePerLitre,
  );
}

Widget _line(String label, int paise, {bool bold = false, Key? key}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(label, style: TextStyle(color: bold ? AppColors.title : AppColors.muted, fontWeight: bold ? FontWeight.w800 : null))),
        Text(formatPaise(paise), key: key, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: AppColors.title)),
      ]),
    );

/// Customer view: fare, toll, diesel and the total, every line an estimate.
class TripCostCard extends StatelessWidget {
  final TripCostPreview cost;
  const TripCostCard({super.key, required this.cost});

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr(context, 'tcTitle'), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            _line(tr(context, 'tcFare'), cost.farePaise),
            _line(tr(context, 'tcToll'), cost.tollPaise),
            _line(tr(context, 'tcFuel'), cost.fuelPaise),
            const Divider(),
            _line(tr(context, 'tcTotal'), cost.total, bold: true, key: const ValueKey('tripCostTotal')),
            const SizedBox(height: 4),
            Text(tr(context, 'tcNote'), style: TextStyle(color: AppColors.faint, fontSize: 12)),
          ],
        ),
      );
}

/// Driver view inside the bid dialog: toll, diesel and what is left of the bid.
class BidMarginPanel extends StatelessWidget {
  final TripCostPreview cost;
  final int? bidPaise;
  const BidMarginPanel({super.key, required this.cost, required this.bidPaise});

  @override
  Widget build(BuildContext context) {
    final c = bidPaise == null ? cost : cost.withFare(bidPaise!);
    final net = c.netMargin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _line(tr(context, 'tcToll'), c.tollPaise),
        _line(tr(context, 'tcFuel'), c.fuelPaise),
        if (bidPaise != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(child: Text(tr(context, 'tcNet'), style: const TextStyle(fontWeight: FontWeight.w800))),
              Text(formatPaise(net),
                  key: const ValueKey('bidNet'),
                  style: TextStyle(fontWeight: FontWeight.w800, color: net < 0 ? Colors.redAccent : AppColors.success)),
            ]),
          ),
        Text(tr(context, 'tcNote'), style: TextStyle(color: AppColors.faint, fontSize: 12)),
      ],
    );
  }
}
