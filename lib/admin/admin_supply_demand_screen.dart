import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/matching/supply_demand.dart';
import '../core/services/admin_console_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';
import '../core/widgets/logistics_labels.dart';

/// Admin > Supply and demand: open loads against free trucks per city and per
/// vehicle type, biggest shortage first. Read once (Refresh to reload), to
/// keep Firestore reads low.
class AdminSupplyDemandScreen extends StatefulWidget {
  /// Test hook; defaults to the live query.
  final Future<SupplyDemand> Function()? load;
  const AdminSupplyDemandScreen({super.key, this.load});

  @override
  State<AdminSupplyDemandScreen> createState() => _AdminSupplyDemandScreenState();
}

class _AdminSupplyDemandScreenState extends State<AdminSupplyDemandScreen> {
  late Future<SupplyDemand> _data = (widget.load ?? AdminConsoleService.supplyDemand)();

  void _refresh() => setState(() {
        _data = (widget.load ?? AdminConsoleService.supplyDemand)();
      });

  Color _color(Balance b) => switch (b) {
        Balance.short => Colors.redAccent,
        Balance.surplus => Colors.orange,
        Balance.balanced => AppColors.success,
      };

  String _label(BuildContext context, Balance b) => tr(context, switch (b) {
        Balance.short => 'sdShort',
        Balance.surplus => 'sdSurplus',
        Balance.balanced => 'sdBalanced',
      });

  Widget _row(BuildContext context, String key, String title, SupplyDemandRow r) => AppCard(
        key: ValueKey(key),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(trf(context, 'sdLine', {'d': r.demand, 's': r.supply}), style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ]),
          ),
          StatusChip(label: _label(context, r.balance), color: _color(r.balance)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'adminSupplyDemand')),
        actions: [IconButton(key: const ValueKey('sdRefresh'), tooltip: tr(context, 'retry'), onPressed: _refresh, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: FutureBuilder<SupplyDemand>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) return ErrorState(error: snap.error, onRetry: _refresh);
          final d = snap.data;
          if (d == null) return const Center(child: CircularProgressIndicator());
          if (d.totalDemand == 0 && d.totalSupply == 0) return EmptyState(icon: Icons.balance_rounded, title: tr(context, 'sdNone'));
          return ListView(padding: const EdgeInsets.all(16), children: [
            AppCard(
              child: Text(trf(context, 'sdTotals', {'d': d.totalDemand, 's': d.totalSupply, 'u': d.unlocatedSupply}), key: const ValueKey('sdTotals'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 8),
            Text(tr(context, 'sdNote'), style: TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 16),
            Text(tr(context, 'sdByCity'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            for (final r in d.cities)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: _row(context, 'sdCity_${r.city}', r.city.isEmpty ? tr(context, 'sdOtherCities') : r.city, r)),
            const SizedBox(height: 12),
            Text(tr(context, 'sdByType'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            for (final e in d.types.entries) Padding(padding: const EdgeInsets.only(bottom: 8), child: _row(context, 'sdType_${e.key}', vehicleTypeLabel(context, e.key), e.value)),
          ]);
        },
      ),
    );
  }
}
