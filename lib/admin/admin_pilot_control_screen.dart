import 'package:flutter/material.dart';

import '../core/admin/pilot_control.dart';
import '../core/l10n/l10n.dart';
import '../core/services/admin_console_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

/// Admin > Pilot control room (MASTER-6 Task 3): today's sign-ups, drivers
/// sharing location, open and unfilled loads, running trips, open SOS and
/// tickets on one page. Read once (Refresh to count again).
class AdminPilotControlScreen extends StatefulWidget {
  /// Test hook; defaults to the live counts.
  final Future<PilotControl> Function()? load;
  const AdminPilotControlScreen({super.key, this.load});

  @override
  State<AdminPilotControlScreen> createState() => _AdminPilotControlScreenState();
}

class _AdminPilotControlScreenState extends State<AdminPilotControlScreen> {
  late Future<PilotControl> _data = (widget.load ?? AdminConsoleService.pilotControl)();

  void _refresh() {
    final next = (widget.load ?? AdminConsoleService.pilotControl)();
    setState(() {
      _data = next;
    });
  }

  Widget _tile(String id, String labelKey, int n, IconData icon, {bool alert = false}) {
    final color = alert && n > 0 ? AppColors.warning : AppColors.primary;
    return AppCard(
      key: ValueKey('pc_$id'),
      child: Row(children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(child: Text(tr(context, labelKey))),
        Text('$n', key: ValueKey('pcN_$id'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'adminPilotControl')),
        actions: [IconButton(key: const ValueKey('pcRefresh'), tooltip: tr(context, 'retry'), onPressed: _refresh, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: FutureBuilder<PilotControl>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) return ErrorState(error: snap.error, onRetry: _refresh);
          final pc = snap.data;
          if (pc == null) return const Center(child: CircularProgressIndicator());
          return ListView(padding: const EdgeInsets.all(16), children: [
            AppCard(
              key: const ValueKey('pcBanner'),
              child: Text(tr(context, pc.needsAttention ? 'pcAttention' : 'pcAllQuiet'), style: TextStyle(fontWeight: FontWeight.w800, color: pc.needsAttention ? AppColors.warning : AppColors.success)),
            ),
            const SizedBox(height: 8),
            _tile('sos', 'pcOpenSos', pc.openSos, Icons.sos_rounded, alert: true),
            const SizedBox(height: 8),
            _tile('unfilled', 'pcUnfilled', pc.unfilledLoads, Icons.hourglass_empty_rounded, alert: true),
            const SizedBox(height: 8),
            _tile('open', 'pcOpenLoads', pc.openLoads, Icons.inventory_2_outlined),
            const SizedBox(height: 8),
            _tile('trips', 'pcRunningTrips', pc.runningTrips, Icons.local_shipping_outlined),
            const SizedBox(height: 8),
            _tile('drivers', 'pcDriversSharing', pc.driversSharing, Icons.my_location_rounded),
            const SizedBox(height: 8),
            _tile('signups', 'pcSignupsToday', pc.signupsToday, Icons.person_add_alt_1_outlined),
            const SizedBox(height: 8),
            _tile('tickets', 'pcOpenTickets', pc.openTickets, Icons.support_agent_rounded),
            const SizedBox(height: 8),
            Text(tr(context, 'pcNote'), style: TextStyle(color: AppColors.faint, fontSize: 12)),
          ]);
        },
      ),
    );
  }
}
