import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n/l10n.dart';
import '../core/models/fleet.dart';
import '../core/models/vehicle.dart';
import '../core/services/auth_helpers.dart';
import '../core/services/fleet_service.dart';
import '../core/services/transporter_service.dart';
import '../core/services/vehicle_service.dart';
import '../core/services/vehicle_type_service.dart';
import '../core/vehicles/vehicle_expenses_screen.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';
import '../core/widgets/logistics_labels.dart';

/// The fleet's vehicles: add one, assign it to an active driver, take it back.
class FleetVehiclesScreen extends StatefulWidget {
  const FleetVehiclesScreen({super.key});

  @override
  State<FleetVehiclesScreen> createState() => _FleetVehiclesScreenState();
}

class _FleetVehiclesScreenState extends State<FleetVehiclesScreen> {
  late final Stream<List<Vehicle>> _vehicles = VehicleService.watchMine().asBroadcastStream();
  late final Stream<List<FleetMember>> _members = FleetService.watchMembers().asBroadcastStream();
  late final Stream<List<Vehicle>> _attached = TransporterService.watchAttached().asBroadcastStream();

  Future<void> _add() async {
    final number = TextEditingController();
    final capacity = TextEditingController();
    final rc = TextEditingController();
    var type = VehicleTypeService.ids.contains('Mini') ? 'Mini' : VehicleTypeService.ids.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: Text(tr(c, 'addVehicle')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(key: const ValueKey('fvNumber'), controller: number, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(labelText: tr(c, 'vehicleNumber')), inputFormatters: [LengthLimitingTextInputFormatter(30)]),
              DropdownButtonFormField<String>(
                isExpanded: true,
                key: const ValueKey('fvType'),
                initialValue: type,
                items: vehicleTypeItems(c, keep: type),
                onChanged: (v) => setS(() => type = v ?? type),
              ),
              TextField(key: const ValueKey('fvCapacity'), controller: capacity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr(c, 'capacityTons')), inputFormatters: [LengthLimitingTextInputFormatter(10)]),
              TextField(key: const ValueKey('fvRc'), controller: rc, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(labelText: tr(c, 'rcNumber')), inputFormatters: [LengthLimitingTextInputFormatter(30)]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr(c, 'cancel'))),
            FilledButton(key: const ValueKey('fvSave'), onPressed: () => Navigator.pop(c, true), child: Text(tr(c, 'save'))),
          ],
        ),
      ),
    );
    final values = (number.text, num.tryParse(capacity.text.trim()), rc.text);
    if (ok != true || !mounted) return;
    final cap = values.$2;
    if (!VehicleService.isValidNumber(values.$1) || cap == null || cap <= 0 || cap > 100 || values.$3.trim().length < 4) {
      return showSnack(context, tr(context, 'invalidVehicleNumber'));
    }
    try {
      await VehicleService.add(number: values.$1, type: type, capacity: cap, rcNumber: values.$3);
      if (mounted) showSnack(context, tr(context, 'vehicleAdded'));
    } on DuplicateVehicleException {
      if (mounted) showSnack(context, tr(context, 'duplicateVehicle'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  Future<void> _assign(Vehicle v, String? driverId) async {
    try {
      await VehicleService.assignDriver(v.id, driverId);
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('fleetAddVehicle'),
        onPressed: _add,
        icon: const Icon(Icons.add_rounded),
        label: Text(tr(context, 'addVehicle')),
      ),
      body: LiveStream<List<Vehicle>>(
        stream: () => _vehicles,
        builder: (context, vehicles) => LiveStream<List<FleetMember>>(
          stream: () => _members,
          compact: true,
          builder: (context, members) {
            final active = [for (final m in members) if (m.active) m];
            return StreamBuilder<List<Vehicle>>(
              stream: _attached,
              builder: (context, attachedSnap) {
            final attached = attachedSnap.data ?? const <Vehicle>[];
            if (vehicles.isEmpty && attached.isEmpty) return EmptyState(icon: Icons.local_shipping_outlined, title: tr(context, 'fleetNoVehicles'));
            return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 90), children: [
              for (final v in vehicles)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    key: ValueKey('fleetVehicle_${v.id}'),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(v.number, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      Text('${vehicleTypeLabel(context, v.type)} • ${formatNum(v.capacity)} T', style: TextStyle(color: AppColors.muted)),
                      Wrap(spacing: 6, children: [StatusChip(label: availabilityLabel(context, v.availability), color: availabilityColor(v.availability))]),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: ValueKey('expenses_${v.id}'),
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => VehicleExpensesScreen(vehicleId: v.id, vehicleNumber: v.number))),
                          icon: const Icon(Icons.receipt_long_outlined, size: 18),
                          label: Text(tr(context, 'exTitle')),
                        ),
                      ),
                      DropdownButtonFormField<String?>(
                        isExpanded: true,
                        key: ValueKey('assign_${v.id}'),
                        initialValue: active.any((m) => m.driverId == v.assignedDriverId) ? v.assignedDriverId : null,
                        decoration: InputDecoration(labelText: tr(context, 'fleetAssignedDriver')),
                        items: [
                          DropdownMenuItem(value: null, child: Text(tr(context, 'fleetNoDriver'))),
                          for (final m in active) DropdownMenuItem(value: m.driverId, child: Text(m.driverName.isEmpty ? maskPhone(m.driverPhone) : m.driverName)),
                        ],
                        onChanged: (d) => _assign(v, d),
                      ),
                    ]),
                  ),
                ),
              if (attached.isNotEmpty) ...[
                Padding(padding: const EdgeInsets.only(top: 8, bottom: 6), child: Text(tr(context, 'trpAttachedVehicles'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                for (final v in attached)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      key: ValueKey('attachedVehicle_${v.id}'),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(v.number, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        Text('${vehicleTypeLabel(context, v.type)} • ${formatNum(v.capacity)} T', style: TextStyle(color: AppColors.muted)),
                        Wrap(spacing: 6, children: [
                          StatusChip(label: tr(context, 'trpAttachedChip'), color: AppColors.primary),
                          StatusChip(label: availabilityLabel(context, v.availability), color: availabilityColor(v.availability)),
                        ]),
                      ]),
                    ),
                  ),
              ],
            ]);
              },
            );
          },
        ),
      ),
    );
  }
}
