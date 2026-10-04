import 'package:flutter/material.dart';

import '../constants/logistics.dart';
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
      _ => 'availAvailable',
    });

Color availabilityColor(String availability) => switch (availability) {
      VehicleAvailability.onTrip => AppColors.primary,
      VehicleAvailability.maintenance => AppColors.warning,
      VehicleAvailability.suspended => Colors.redAccent,
      _ => AppColors.success,
    };

/// Translated [VehicleDocKind] name.
String vehicleDocLabel(BuildContext context, String kind) => tr(context, switch (kind) {
      VehicleDocKind.insurance => 'docInsurance',
      VehicleDocKind.puc => 'docPuc',
      VehicleDocKind.fitness => 'docFitness',
      _ => 'docPermit',
    });
