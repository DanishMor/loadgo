import 'package:flutter/material.dart';

import '../core/models/vehicle.dart';
import '../core/services/vehicle_service.dart';
import '../core/widgets/common.dart';
import '../core/l10n/l10n.dart';
import '../core/widgets/live_stream.dart';
import 'add_vehicle_screen.dart';
import '../core/widgets/logistics_labels.dart';
import 'vehicle_documents_screen.dart';

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
    final now = DateTime.now();
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
                Text(v.number, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.title)),
                const SizedBox(height: 4),
                Text('${vehicleTypeLabel(context, v.type)} • ${formatNum(v.capacity)} T • RC ${v.rcNumber}',
                    style: TextStyle(color: AppColors.muted, fontSize: 13)),
                if (_profileLine(context, v) case final line?)
                  Text(line, key: ValueKey('profile_${v.id}'), style: TextStyle(color: AppColors.muted, fontSize: 12)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    StatusChip(
                      label: tr(context, v.isActive ? 'active' : 'inactive'),
                      color: v.isActive ? AppColors.success : AppColors.faint,
                    ),
                    StatusChip(label: availabilityLabel(context, v.availability), color: availabilityColor(v.availability)),
                    StatusChip(
                      label: tr(context, v.rcImageUrl != null ? 'rcUploaded' : 'rcMissing'),
                      color: v.rcImageUrl != null ? AppColors.success : AppColors.warning,
                    ),
                    if (v.expiredDocs(now).isNotEmpty)
                      StatusChip(label: tr(context, 'docExpired'), color: Colors.redAccent)
                    else if (v.docsExpiringWithin(now).isNotEmpty)
                      StatusChip(label: trf(context, 'docsExpiringBanner', {'n': v.docsExpiringWithin(now).length}), color: AppColors.warning),
                    if (v.serviceDue(now)) StatusChip(label: tr(context, 'serviceDue'), color: AppColors.warning),
                    if (v.tyreDue(now)) StatusChip(label: tr(context, 'tyreDue'), color: AppColors.warning),
                  ],
                ),
                TextButton.icon(
                  key: ValueKey('docs_${v.id}'),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => VehicleDocumentsScreen(vehicle: v))),
                  icon: const Icon(Icons.assignment_outlined, size: 18),
                  label: Text(tr(context, 'vehicleDocs')),
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

/// "Closed body • Diesel • 6.1 × 2.4 × 2.4 m" or null when the profile is empty.
String? _profileLine(BuildContext context, Vehicle v) {
  final p = v.profile;
  final parts = [
    if (p.bodyType != null) tr(context, 'body_${p.bodyType}'),
    if (p.fuel != null) tr(context, 'fuel_${p.fuel}'),
    ?p.dimensionsText,
  ];
  return parts.isEmpty ? null : parts.join(' • ');
}
