import 'package:flutter/material.dart';

import '../../core/constants/logistics.dart';
import '../../core/models/load.dart';
import '../../core/share_text.dart';
import '../../core/widgets/common.dart';
import '../../main.dart';
import '../shared/vehicle_type_widgets.dart';

String loadStatusLabel(BuildContext context, String status, {bool cancelled = false}) => switch (status) {
      LoadStatus.closed when cancelled => tr(context, 'statusCancelled'),
      LoadStatus.open => tr(context, 'statusOpen'),
      LoadStatus.matched => tr(context, 'statusMatched'),
      LoadStatus.closed => tr(context, 'statusClosed'),
      _ => status,
    };

Color loadStatusColor(String status, {bool cancelled = false}) => switch (status) {
      LoadStatus.closed when cancelled => AppColors.faint,
      LoadStatus.open => AppColors.primary,
      LoadStatus.matched => AppColors.warning,
      _ => AppColors.success,
    };

/// Card showing pickup → drop, weight, vehicle type and budget.
/// [action] renders below the details (e.g. Accept / View booking).
class LoadCard extends StatelessWidget {
  final Load load;
  final bool showStatus;
  final Widget? action;

  const LoadCard({super.key, required this.load, this.showStatus = false, this.action});

  Widget _meta(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.muted),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: AppColors.body, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: RouteText(pickup: load.pickup, drop: load.drop)),
              if (showStatus) ...[
                const SizedBox(width: 8),
                StatusChip(
                  label: loadStatusLabel(context, load.status, cancelled: load.cancelled),
                  color: loadStatusColor(load.status, cancelled: load.cancelled),
                ),
              ],
              CopyShareButton(
                text: loadShareText(load),
                tooltip: tr(context, 'share'),
                copiedMessage: tr(context, 'copiedToClipboard'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _meta(Icons.scale_outlined, '${formatNum(load.weight)} T'),
              _meta(Icons.local_shipping_outlined, vehicleTypeLabel(context, load.vehicleType)),
              _meta(Icons.inventory_2_outlined, load.cargoType),
              _meta(Icons.calendar_today_outlined, formatDate(load.pickupDate)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            load.budget == null ? '${tr(context, 'budget')}: ${tr(context, 'budgetNegotiable')}' : formatRupees(load.budget!),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary),
          ),
          if (load.notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(load.notes, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          ],
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}
