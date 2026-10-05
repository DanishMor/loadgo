import 'package:flutter/material.dart';

import '../core/documents/doc_expiry.dart';
import '../core/l10n/l10n.dart';
import '../core/models/vehicle.dart';
import '../core/widgets/common.dart';
import '../core/widgets/logistics_labels.dart';

/// Driver Home: red card when the licence is expired (no loads) and one line
/// per vehicle held back by an expired insurance / permit / fitness paper.
class DocSuspensionBanner extends StatelessWidget {
  final Stream<List<Vehicle>> vehicles;
  final Map<String, dynamic>? profile;
  final VoidCallback onOpenVehicles;
  final VoidCallback onOpenLicence;

  const DocSuspensionBanner({
    super.key,
    required this.vehicles,
    required this.profile,
    required this.onOpenVehicles,
    required this.onOpenLicence,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Vehicle>>(
      stream: vehicles,
      builder: (context, snap) {
        final now = DateTime.now();
        final held = [for (final v in snap.data ?? const <Vehicle>[]) if (v.papersBlocked(now)) v];
        final licence = DocExpiry.licenceBlocked(profile, now);
        if (!licence && held.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(children: [
            if (licence)
              AppCard(
                key: const ValueKey('licenceBanner'),
                onTap: onOpenLicence,
                child: Row(children: [
                  const Icon(Icons.block_rounded, color: Colors.redAccent, size: 28),
                  const SizedBox(width: 12),
                  Expanded(child: Text(tr(context, 'licenceExpiredBanner'), style: const TextStyle(fontWeight: FontWeight.w700))),
                ]),
              ),
            for (final v in held)
              AppCard(
                key: ValueKey('heldVehicle_${v.id}'),
                onTap: onOpenVehicles,
                child: Row(children: [
                  const Icon(Icons.local_shipping_outlined, color: Colors.redAccent, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      trf(context, 'vehicleDocsBanner', {
                        'number': v.number,
                        'docs': v.blockingExpired(now).map((k) => vehicleDocLabel(context, k)).join(', '),
                      }),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ]),
              ),
          ]),
        );
      },
    );
  }
}
