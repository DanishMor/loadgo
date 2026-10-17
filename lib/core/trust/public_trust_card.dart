import 'package:flutter/material.dart';

import '../app_info.dart';
import '../features/features.dart';
import '../l10n/l10n.dart';
import '../theme/design_tokens.dart';
import '../widgets/feature_gate.dart';
import '../widgets/ds/status_badge.dart';
import 'public_trust.dart';

String _monthName(String yyyyMm) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final parts = yyyyMm.split('-');
  final m = int.tryParse(parts[1]) ?? 0;
  return m >= 1 && m <= 12 ? '${months[m - 1]} ${parts[0]}' : yyyyMm;
}

/// G19: what a customer may know about a driver, from `public_trust/{uid}` which only the server writes: finished
/// trips, star rating, a verified mark and the month they joined. No name, phone or papers. Behind `tripTrustCard`
/// (OFF). A missing summary (server not deployed) shows nothing; a driver with no trips yet shows "New on Load 20".
class PublicTrustCard extends StatelessWidget {
  final String driverId;
  final Stream<PublicTrust?>? source;

  const PublicTrustCard({super.key, required this.driverId, this.source});

  @override
  Widget build(BuildContext context) {
    if (driverId.isEmpty) return const SizedBox.shrink();
    return FeatureGate(
      featureKey: FeatureKey.tripTrustCard,
      child: StreamBuilder<PublicTrust?>(
        stream: source ?? PublicTrust.watch(driverId),
        builder: (context, snap) {
          if (snap.hasError) return const SizedBox.shrink();
          final t = snap.data;
          if (t == null) return const SizedBox.shrink();
          final chips = <Widget>[];
          if (t.verified) {
            chips.add(StatusBadge(key: const ValueKey('ptVerified'), label: tr(context, 'ptVerified'), tone: StatusTone.success, icon: Icons.verified_rounded));
          }
          if (t.hasRating) {
            chips.add(StatusBadge(
              key: const ValueKey('ptRating'),
              label: trf(context, 'ptRating', {'r': t.rating!.toStringAsFixed(1), 'n': t.ratingCount}),
              tone: StatusTone.neutral,
              icon: Icons.star_rounded,
            ));
          }
          if (t.trips > 0) {
            chips.add(StatusBadge(
              key: const ValueKey('ptTrips'),
              label: t.trips == 1 ? tr(context, 'ptTripsOne') : trf(context, 'ptTrips', {'n': t.trips}),
              tone: StatusTone.neutral,
              icon: Icons.local_shipping_outlined,
            ));
          }
          if (t.since != null) {
            chips.add(StatusBadge(
              key: const ValueKey('ptSince'),
              label: trf(context, 'ptSince', {'month': _monthName(t.since!)}),
              tone: StatusTone.neutral,
              icon: Icons.calendar_month_outlined,
            ));
          }
          if (chips.isEmpty) {
            chips.add(StatusBadge(key: const ValueKey('ptNew'), label: trf(context, 'ptNew', {'app': AppInfo.name}), tone: StatusTone.neutral, icon: Icons.fiber_new_rounded));
          }
          return Padding(
            key: const ValueKey('publicTrustCard'),
            padding: const EdgeInsets.only(top: DsSpace.s2),
            child: Wrap(spacing: DsSpace.s2, runSpacing: DsSpace.s1, children: chips),
          );
        },
      ),
    );
  }
}
