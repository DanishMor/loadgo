import 'package:flutter/material.dart';

import '../core/analytics/trip_stats.dart';
import '../core/l10n/l10n.dart';
import '../core/services/analytics_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/stat_tile.dart';

/// Shipments, spend, top routes and success rate for a customer.
class CustomerAnalyticsScreen extends StatelessWidget {
  const CustomerAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'myAnalytics'))),
      body: FutureBuilder<CustomerStats>(
        future: AnalyticsService.customer(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text(tr(context, 'somethingWrong')));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final s = snap.data!;
          final noData = tr(context, 'statNoData');
          return ListView(padding: const EdgeInsets.all(16), children: [
            StatTile(icon: Icons.inventory_2_outlined, label: tr(context, 'statShipments'), value: '${s.shipments}'),
            const SizedBox(height: 10),
            StatTile(icon: Icons.check_circle_outline_rounded, label: tr(context, 'statDelivered'), value: '${s.delivered}'),
            const SizedBox(height: 10),
            StatTile(icon: Icons.currency_rupee_rounded, label: tr(context, 'statSpend'), value: formatPaise(s.spendPaise)),
            const SizedBox(height: 10),
            StatTile(
              icon: Icons.trending_up_rounded,
              label: tr(context, 'statSuccessRate'),
              value: s.successRate == null ? '–' : percentText(s.successRate!),
            ),
            const SizedBox(height: 16),
            Text(tr(context, 'statTopRoutes'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            if (s.topRoutes.isEmpty) Text(noData, style: const TextStyle(color: AppColors.muted)),
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
