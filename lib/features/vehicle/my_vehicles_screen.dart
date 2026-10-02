import 'package:flutter/material.dart';

import '../../core/models/vehicle.dart';
import '../../core/services/vehicle_service.dart';
import '../../core/widgets/common.dart';
import '../../main.dart';
import '../shared/live_stream.dart';
import 'add_vehicle_screen.dart';

void openEditVehicle(BuildContext context, Vehicle vehicle) {
  Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => AddVehicleScreen(vehicle: vehicle)));
}

/// Opens the add-vehicle form; returns true when a vehicle was saved.
Future<bool> openAddVehicle(BuildContext context, {bool prefillFromProfile = false}) async {
  final added = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => AddVehicleScreen(prefillFromProfile: prefillFromProfile)),
  );
  return added == true;
}

class MyVehiclesScreen extends StatelessWidget {
  const MyVehiclesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        title: Text(tr(context, 'myVehicles'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openAddVehicle(context),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text(tr(context, 'addVehicle')),
      ),
      body: SafeArea(
        child: LiveStream<List<Vehicle>>(
          stream: VehicleService.watchMine,
          builder: (context, vehicles) {
            if (vehicles.isEmpty) {
              return EmptyState(
                icon: Icons.local_shipping_rounded,
                title: tr(context, 'noVehicleTitle'),
                subtitle: tr(context, 'noVehicleSub'),
                action: SizedBox(
                  width: 220,
                  child: PrimaryButton(
                    label: tr(context, 'addVehicle'),
                    icon: Icons.add_rounded,
                    onPressed: () => openAddVehicle(context, prefillFromProfile: true),
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
              itemCount: vehicles.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _VehicleCard(key: ValueKey(vehicles[i].id), vehicle: vehicles[i]),
            );
          },
        ),
      ),
    );
  }
}

class _VehicleCard extends StatefulWidget {
  final Vehicle vehicle;
  const _VehicleCard({super.key, required this.vehicle});

  @override
  State<_VehicleCard> createState() => _VehicleCardState();
}

class _VehicleCardState extends State<_VehicleCard> {
  bool _busy = false;

  Future<void> _toggle(bool value) async {
    setState(() => _busy = true);
    try {
      await VehicleService.setActive(widget.vehicle.id, value);
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vehicle;
    return AppCard(
      onTap: () => openEditVehicle(context, v),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.local_shipping_rounded, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v.number, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.title)),
                const SizedBox(height: 4),
                Text('${v.type} • ${formatNum(v.capacity)} T • RC ${v.rcNumber}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    StatusChip(
                      label: tr(context, v.isActive ? 'active' : 'inactive'),
                      color: v.isActive ? AppColors.success : AppColors.faint,
                    ),
                    StatusChip(
                      label: tr(context, v.rcImageUrl != null ? 'rcUploaded' : 'rcMissing'),
                      color: v.rcImageUrl != null ? AppColors.success : AppColors.warning,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Switch(value: v.isActive, onChanged: _busy ? null : _toggle),
        ],
      ),
    );
  }
}
