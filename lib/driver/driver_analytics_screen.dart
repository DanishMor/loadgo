import 'package:flutter/material.dart';

import '../core/analytics/trip_stats.dart';
import '../core/l10n/l10n.dart';
import '../core/services/analytics_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/stat_tile.dart';

/// Trips, earnings, offer acceptance and cancel rate for a driver.
class DriverAnalyticsScreen extends StatelessWidget {
  const DriverAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'myAnalytics'))),
      body: FutureBuilder<DriverStats>(
        future: AnalyticsService.driver(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text(tr(context, 'somethingWrong')));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final s = snap.data!;
          String rate(num? r) => r == null ? '–' : percentText(r);
          return ListView(padding: const EdgeInsets.all(16), children: [
            StatTile(icon: Icons.route_rounded, label: tr(context, 'statTrips'), value: '${s.trips}'),
            const SizedBox(height: 10),
            StatTile(icon: Icons.currency_rupee_rounded, label: tr(context, 'statEarnings'), value: formatPaise(s.earningsPaise)),
            const SizedBox(height: 10),
            StatTile(icon: Icons.handshake_outlined, label: tr(context, 'statAcceptRate'), value: rate(s.acceptanceRate)),
            const SizedBox(height: 10),
            StatTile(icon: Icons.cancel_outlined, label: tr(context, 'statCancelRate'), value: rate(s.cancelRate)),
            const SizedBox(height: 16),
            Text(tr(context, 'statTopRoutes'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            if (s.topRoutes.isEmpty) Text(tr(context, 'statNoData'), style: TextStyle(color: AppColors.muted)),
            for (final r in s.topRoutes)
              ListTile(
                key: ValueKey('route_${r.route}'),
                contentPadding: EdgeInsets.zero,
                title: Text(r.route),
                trailing: Text('${r.count}', style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
          ]);
        },
      ),
    );
  }
}
