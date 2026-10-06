import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/vehicle.dart';
import '../core/widgets/common.dart';

/// Number of vehicle papers expiring within 30 days (or expired) and
/// vehicles whose service is due, across [vehicles].
({int expiringDocs, int serviceDue}) vehicleAlerts(List<Vehicle> vehicles, DateTime now) => (
  expiringDocs: vehicles.fold(0, (n, v) => n + v.docsExpiringWithin(now).length),
  serviceDue: vehicles.where((v) => v.serviceDue(now)).length,
);

/// Driver Home warning card; hidden when nothing needs attention.
class VehicleAlertsBanner extends StatelessWidget {
  final Stream<List<Vehicle>> vehicles;
  final VoidCallback onTap;

  const VehicleAlertsBanner({super.key, required this.vehicles, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Vehicle>>(
      stream: vehicles,
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final a = vehicleAlerts(snap.data!, DateTime.now());
        if (a.expiringDocs == 0 && a.serviceDue == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: AppCard(
            onTap: onTap,
            child: Row(
              children: [
                Badge(
                  label: Text('${a.expiringDocs + a.serviceDue}'),
                  child: const Icon(Icons.assignment_late_rounded, color: AppColors.warning, size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (a.expiringDocs > 0)
                        Text(
                          trf(context, 'docsExpiringBanner', {'n': a.expiringDocs}),
                          style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.title),
                        ),
                      if (a.serviceDue > 0)
                        Text(tr(context, 'serviceDue'), style: TextStyle(fontSize: 13, color: AppColors.muted)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: AppColors.faint),
              ],
            ),
          ),
        );
      },
    );
  }
}
