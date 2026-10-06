import 'package:flutter/material.dart';

import '../constants/logistics.dart';
import '../models/load.dart';
import '../services/backend.dart';
import '../share/share_widgets.dart';
import 'common.dart';
import '../l10n/l10n.dart';
import 'logistics_labels.dart';
import '../network/share_load_sheet.dart';

String loadStatusLabel(BuildContext context, String status, {bool cancelled = false}) => switch (status) {
      LoadStatus.closed when cancelled => tr(context, 'statusCancelled'),
      LoadStatus.open => tr(context, 'statusOpen'),
      LoadStatus.awaitingApproval => tr(context, 'bizAwaiting'),
      LoadStatus.matched => tr(context, 'statusMatched'),
      LoadStatus.closed => tr(context, 'statusClosed'),
      _ => status,
    };

Color loadStatusColor(String status, {bool cancelled = false}) => switch (status) {
      LoadStatus.closed when cancelled => AppColors.faint,
      LoadStatus.open => AppColors.primary,
      LoadStatus.awaitingApproval => AppColors.warning,
      LoadStatus.matched => AppColors.warning,
      _ => AppColors.success,
    };

/// Card showing pickup → drop, weight, vehicle type and budget.
/// [action] renders below the details (e.g. Accept / View booking).
class LoadCard extends StatelessWidget {
  final Load load;
  final bool showStatus;
  final Widget? action;

  /// Drivers get a button that sends the card to a connection or group.
  final bool networkShare;

  const LoadCard({super.key, required this.load, this.showStatus = false, this.action, this.networkShare = false});

  Widget _meta(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.muted),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: AppColors.body, fontSize: 13, fontWeight: FontWeight.w600)),
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
              if (networkShare)
                IconButton(
                  key: ValueKey('networkShare_${load.id}'),
                  tooltip: tr(context, 'netShareLoad'),
                  icon: const Icon(Icons.groups_2_outlined),
                  onPressed: () => showShareToNetwork(context, load),
                ),
              LoadShareButton(load: load),
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
              if (load.scheduledAt != null) _meta(Icons.event_available_rounded, trf(context, 'scheduledFor', {'when': formatDateTime(load.scheduledAt!)})),
              if (load.scheduledAt == null && load.pickupSlot != PickupSlot.any) _meta(Icons.schedule_rounded, pickupSlotLabel(context, load.pickupSlot)),
              if (load.extraStopCount > 0) _meta(Icons.alt_route_rounded, trf(context, 'extraStops', {'n': load.extraStopCount})),
              if (load.bookingType == BookingType.rental && load.rentalHours != null)
                _meta(Icons.timer_outlined, trf(context, 'rentalHoursChip', {'h': load.rentalHours!})),
              if (load.bookingType == BookingType.movers && load.movers != null)
                _meta(Icons.chair_alt_outlined, trf(context, 'moversChip', {'n': load.movers!.units, 'floor': load.movers!.floor})),
              if (load.instant) _meta(Icons.bolt_rounded, tr(context, 'instantLabel')),
              if (load.visibility != LoadVisibility.public) _meta(Icons.lock_outline_rounded, tr(context, 'visPrivateChip')),
              if (load.fragile) _meta(Icons.broken_image_outlined, tr(context, 'fragileChip')),
              if (load.highValue) _meta(Icons.diamond_outlined, tr(context, 'highValueChip')),
              if (load.helpers > 0) _meta(Icons.people_outline_rounded, trf(context, 'helpersChip', {'n': load.helpers})),
              if (load.invitedDriverId != null)
                _meta(Icons.how_to_reg_outlined, load.invitedDriverId == Backend.uid ? tr(context, 'reservedForYou') : tr(context, 'reservedForDriver')),
              if (load.promoCode != null) _meta(Icons.local_offer_outlined, '${load.promoCode} -${formatPaise(load.promoDiscountPaise)}'),
              if (load.estimate != null) _meta(Icons.calculate_outlined, formatPaise(load.estimate!.total)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            load.budget == null ? '${tr(context, 'budget')}: ${tr(context, 'budgetNegotiable')}' : formatRupees(load.budget!),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary),
          ),
          if (load.notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(load.notes, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.muted, fontSize: 13)),
          ],
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}
