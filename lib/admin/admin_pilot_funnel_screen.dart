import 'package:flutter/material.dart';

import '../core/admin/pilot_funnel.dart';
import '../core/l10n/l10n.dart';
import '../core/services/admin_console_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

/// Admin > Pilot funnel: where customers, drivers and transporters stop on the
/// way to their first delivery. Read once (Refresh to count again).
class AdminPilotFunnelScreen extends StatefulWidget {
  /// Test hook; defaults to the live query.
  final Future<PilotFunnel> Function()? load;
  const AdminPilotFunnelScreen({super.key, this.load});

  @override
  State<AdminPilotFunnelScreen> createState() => _AdminPilotFunnelScreenState();
}

class _AdminPilotFunnelScreenState extends State<AdminPilotFunnelScreen> {
  late Future<PilotFunnel> _data = (widget.load ?? AdminConsoleService.pilotFunnel)();

  void _refresh() {
    final next = (widget.load ?? AdminConsoleService.pilotFunnel)();
    setState(() {
      _data = next;
    });
  }

  Widget _section(BuildContext context, String id, String titleKey, List<FunnelStep> steps) {
    final top = steps.isEmpty ? 0 : steps.first.count;
    final drop = PilotFunnel.biggestDrop(steps);
    return AppCard(
      key: ValueKey('funnel_$id'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(context, titleKey), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (final s in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(tr(context, s.key))),
                Text('${s.count}', key: ValueKey('funnel_${id}_${s.key}'), style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 3),
              LinearProgressIndicator(value: top == 0 ? 0 : s.count / top, minHeight: 6, borderRadius: BorderRadius.circular(3)),
            ]),
          ),
        if (drop != null)
          Text(trf(context, 'pfBiggestDrop', {'from': tr(context, drop.$1), 'to': tr(context, drop.$2), 'n': drop.$3}), key: ValueKey('funnelDrop_$id'), style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'adminPilotFunnel')),
        actions: [IconButton(key: const ValueKey('pfRefresh'), tooltip: tr(context, 'retry'), onPressed: _refresh, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: FutureBuilder<PilotFunnel>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) return ErrorState(error: snap.error, onRetry: _refresh);
          final f = snap.data;
          if (f == null) return const Center(child: CircularProgressIndicator());
          if (f.customers.first.count + f.drivers.first.count + f.transporters.first.count == 0) {
            return EmptyState(icon: Icons.filter_alt_outlined, title: tr(context, 'pfNone'));
          }
          return ListView(padding: const EdgeInsets.all(16), children: [
            _section(context, 'customers', 'pfCustomers', f.customers),
            const SizedBox(height: 12),
            _section(context, 'drivers', 'pfDrivers', f.drivers),
            const SizedBox(height: 12),
            _section(context, 'transporters', 'pfTransporters', f.transporters),
            const SizedBox(height: 8),
            Text(tr(context, 'pfNote'), style: TextStyle(color: AppColors.faint, fontSize: 12)),
          ]);
        },
      ),
    );
  }
}
