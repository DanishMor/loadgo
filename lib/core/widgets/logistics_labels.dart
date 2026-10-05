import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/logistics.dart';
import '../models/offer.dart';
import '../models/vehicle_type.dart';
import '../services/vehicle_type_service.dart';
import 'common.dart';
import '../l10n/l10n.dart';

/// Translated display name of a vehicle type id.
String vehicleTypeLabel(BuildContext context, String id) {
  final info = VehicleTypeService.byId(id);
  if (info?.labelKey != null) return tr(context, info!.labelKey!);
  final feet = RegExp(r'^(\d+)ft$').firstMatch(id);
  if (feet != null) return trf(context, 'vtFeet', {'n': feet.group(1)!});
  return info?.name ?? id;
}

/// "Usually 2.5–4 T" for [info].
String vehicleTypeRange(BuildContext context, VehicleTypeInfo info) =>
    trf(context, 'vtCapacityRange', {'min': formatNum(info.minTons), 'max': formatNum(info.maxTons)});

/// Dropdown items for the active vehicle types (plus [keep] if it is a
/// legacy/inactive id, so an existing value stays selectable).
List<DropdownMenuItem<String>> vehicleTypeItems(BuildContext context, {String? keep}) {
  final ids = VehicleTypeService.ids;
  return [
    for (final id in ids) DropdownMenuItem(value: id, child: Text(vehicleTypeLabel(context, id))),
    if (keep != null && !ids.contains(keep)) DropdownMenuItem(value: keep, child: Text(vehicleTypeLabel(context, keep))),
  ];
}

/// Translated [VehicleAvailability] value.
String availabilityLabel(BuildContext context, String availability) => tr(context, switch (availability) {
      VehicleAvailability.onTrip => 'availOnTrip',
      VehicleAvailability.maintenance => 'availMaintenance',
      VehicleAvailability.suspended => 'availSuspended',
      VehicleAvailability.docExpired => 'availDocExpired',
      _ => 'availAvailable',
    });

Color availabilityColor(String availability) => switch (availability) {
      VehicleAvailability.onTrip => AppColors.primary,
      VehicleAvailability.maintenance => AppColors.warning,
      VehicleAvailability.suspended || VehicleAvailability.docExpired => Colors.redAccent,
      _ => AppColors.success,
    };

/// Translated [VehicleDocKind] name.
String vehicleDocLabel(BuildContext context, String kind) => tr(context, switch (kind) {
      VehicleDocKind.insurance => 'docInsurance',
      VehicleDocKind.puc => 'docPuc',
      VehicleDocKind.fitness => 'docFitness',
      _ => 'docPermit',
    });

/// Translated [PickupSlot] value.
String pickupSlotLabel(BuildContext context, String slot) => tr(context, switch (slot) {
      PickupSlot.morning => 'slotMorning',
      PickupSlot.midday => 'slotMidday',
      PickupSlot.afternoon => 'slotAfternoon',
      PickupSlot.evening => 'slotEvening',
      _ => 'slotAny',
    });

/// Translated [OfferStatus] value.
String offerStatusLabel(BuildContext context, String status) => tr(context, switch (status) {
      OfferStatus.countered => 'offerCountered',
      OfferStatus.selected => 'offerSelected',
      OfferStatus.confirmed => 'offerConfirmed',
      OfferStatus.rejected => 'offerRejected',
      OfferStatus.withdrawn => 'offerWithdrawn',
      _ => 'offerPending',
    });

Color offerStatusColor(String status) => switch (status) {
      OfferStatus.countered => AppColors.warning,
      OfferStatus.selected => AppColors.primary,
      OfferStatus.confirmed => AppColors.success,
      OfferStatus.rejected || OfferStatus.withdrawn => AppColors.faint,
      _ => AppColors.muted,
    };

/// Asks for a whole-rupee price; returns paise, or null when cancelled.
Future<int?> askPricePaise(BuildContext context, {required String title, required String label, int? initialPaise, String? note}) =>
    showDialog<int>(
      context: context,
      builder: (_) => _PriceDialog(title: title, label: label, initialPaise: initialPaise, note: note),
    );

class _PriceDialog extends StatefulWidget {
  final String title;
  final String label;
  final int? initialPaise;
  final String? note;

  const _PriceDialog({required this.title, required this.label, this.initialPaise, this.note});

  @override
  State<_PriceDialog> createState() => _PriceDialogState();
}

class _PriceDialogState extends State<_PriceDialog> {
  late final _ctrl = TextEditingController(text: widget.initialPaise == null ? '' : '${widget.initialPaise! ~/ 100}');
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              key: const ValueKey('priceField'),
              controller: _ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: widget.label, prefixIcon: const Icon(Icons.currency_rupee_rounded)),
              validator: (v) {
                final n = int.tryParse(v?.trim() ?? '');
                return (n == null || n <= 0 || n > 1000000) ? tr(context, 'invalidNumber') : null;
              },
            ),
            if (widget.note != null) ...[
              const SizedBox(height: 8),
              Text(widget.note!, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr(context, 'cancel'))),
        FilledButton(
          key: const ValueKey('priceSubmit'),
          onPressed: () {
            if (_formKey.currentState!.validate()) Navigator.of(context).pop(int.parse(_ctrl.text.trim()) * 100);
          },
          child: Text(tr(context, 'save')),
        ),
      ],
    );
  }
}

/// Translated [BookingStatus] value.
String bookingStatusLabel(BuildContext context, String status) => switch (status) {
      BookingStatus.accepted => tr(context, 'statusAccepted'),
      BookingStatus.driverArriving => tr(context, 'statusDriverArriving'),
      BookingStatus.loading => tr(context, 'statusLoading'),
      BookingStatus.pickedUp => tr(context, 'statusPickedUp'),
      BookingStatus.inTransit => tr(context, 'statusInTransit'),
      BookingStatus.unloading => tr(context, 'statusUnloading'),
      BookingStatus.delivered => tr(context, 'statusDelivered'),
      BookingStatus.cancelled => tr(context, 'statusCancelled'),
      _ => status,
    };

Color bookingStatusColor(String status) => switch (status) {
      BookingStatus.accepted => AppColors.primary,
      BookingStatus.delivered => AppColors.success,
      BookingStatus.cancelled => Colors.redAccent,
      _ => AppColors.warning,
    };
