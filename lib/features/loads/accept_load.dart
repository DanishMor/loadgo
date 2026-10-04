import 'package:flutter/material.dart';

import '../../core/models/load.dart';
import '../../core/models/vehicle.dart';
import '../../core/services/booking_service.dart';
import '../../core/services/vehicle_service.dart';
import '../../core/widgets/common.dart';
import '../../main.dart';
import '../vehicle/my_vehicles_screen.dart';
import '../../core/widgets/vehicle_type_widgets.dart';

/// Lets the driver pick one of their active vehicles and confirm. Returns null
/// when cancelled.
Future<Vehicle?> _chooseVehicle(BuildContext context, Load load, List<Vehicle> vehicles) {
  return showModalBottomSheet<Vehicle>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RouteText(pickup: load.pickup, drop: load.drop),
            const SizedBox(height: 4),
            Text('${formatNum(load.weight)} T • ${vehicleTypeLabel(context, load.vehicleType)} • ${formatDate(load.pickupDate)}',
                style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 16),
            Text(tr(sheetContext, 'chooseVehicle'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final v in vehicles)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.local_shipping_rounded, color: AppColors.primary),
                      title: Text(v.number, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        '${vehicleTypeLabel(context, v.type)} • ${formatNum(v.capacity)} T'
                        '${v.canTakeBooking ? '' : ' • ${availabilityLabel(context, v.availability)}'}',
                      ),
                      trailing: FilledButton(
                        onPressed: v.canTakeBooking ? () => Navigator.of(sheetContext).pop(v) : null,
                        child: Text(tr(sheetContext, 'accept')),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Full accept flow: ensure an active vehicle, confirm, then book atomically.
/// [onBusy] is toggled only around network calls, not while the sheet is open.
/// Returns the booking id on success.
Future<String?> acceptLoadFlow(BuildContext context, Load load, {ValueChanged<bool>? onBusy}) async {
  final List<Vehicle> vehicles;
  onBusy?.call(true);
  try {
    vehicles = await VehicleService.fetchMyActive();
  } catch (_) {
    if (context.mounted) showSnack(context, tr(context, 'somethingWrong'));
    return null;
  } finally {
    onBusy?.call(false);
  }
  if (!context.mounted) return null;

  if (vehicles.isEmpty) {
    showSnack(context, tr(context, 'needVehicleFirst'));
    await openAddVehicle(context, prefillFromProfile: true);
    return null;
  }

  final vehicle = await _chooseVehicle(context, load, vehicles);
  if (vehicle == null || !context.mounted) return null;

  onBusy?.call(true);
  try {
    final bookingId = await BookingService.accept(loadId: load.id, vehicle: vehicle);
    if (context.mounted) showSnack(context, tr(context, 'loadAccepted'));
    return bookingId;
  } on LoadUnavailableException {
    if (context.mounted) showSnack(context, tr(context, 'loadUnavailable'));
  } on VehicleBusyException {
    if (context.mounted) showSnack(context, tr(context, 'vehicleBusy'));
  } catch (_) {
    if (context.mounted) showSnack(context, tr(context, 'somethingWrong'));
  } finally {
    onBusy?.call(false);
  }
  return null;
}
