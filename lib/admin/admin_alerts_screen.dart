import 'package:flutter/material.dart';

import '../core/admin/admin_alerts.dart';
import '../core/l10n/l10n.dart';
import '../core/services/admin_console_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';
import 'admin_fraud_cases_screen.dart';
import 'admin_lists.dart';
import 'admin_signals_screen.dart';
import 'admin_violations_screen.dart';
import 'flagged_users_screen.dart';

/// Admin > Alerts (MASTER-6 Task 14): what needs a person now, most urgent
/// first, for this staff role. Tap an alert to open the screen that works on it.
class AdminAlertsScreen extends StatefulWidget {
  /// Test hook; defaults to the live counts.
  final Future<List<AdminAlert>> Function()? load;
  const AdminAlertsScreen({super.key, this.load});

  @override
  State<AdminAlertsScreen> createState() => _AdminAlertsScreenState();
}

class _AdminAlertsScreenState extends State<AdminAlertsScreen> {
  late Future<List<AdminAlert>> _data = (widget.load ?? AdminConsoleService.alerts)();

  void _refresh() {
    final next = (widget.load ?? AdminConsoleService.alerts)();
    setState(() {
      _data = next;
    });
  }

  static Widget? _screenFor(String area) => switch (area) {
        'adminSos' => const AdminSosScreen(),
        'adminFraudCases' => const AdminFraudCasesScreen(),
        'adminSignals' => const AdminSignalsScreen(),
        'pcAdminViolations' => const AdminViolationsScreen(),
        'flaggedUsers' => const FlaggedUsersScreen(),
        'adminVehicles' => const AdminVehiclesScreen(),
        'adminDeletionRequests' => const AdminDeletionRequestsScreen(),
        _ => null,
      };

  String _text(AdminAlert a) => switch (a.id) {
        'sos' => trf(context, 'alSos', {'n': a.count}),
        'fraud' => trf(context, 'alFraud', {'n': a.count}),
        'signals' => trf(context, 'alSignals', {'n': a.count}),
        'strikes' => trf(context, 'alStrikes', {'n': a.count}),
        'held' => trf(context, 'alHeld', {'n': a.count}),
        'deletions' => trf(context, 'alDeletions', {'n': a.count}),
        _ => trf(context, 'alDocs', {'n': a.count, 'day': a.peakDay == null ? '' : '${a.peakDay!.day}/${a.peakDay!.month}', 'm': a.peakCount}),
      };

  Color _color(AlertLevel l) => switch (l) { AlertLevel.critical => const Color(0xFFD92D20), AlertLevel.warning => AppColors.warning, AlertLevel.info => AppColors.primary };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'adminAlerts')), actions: [IconButton(key: const ValueKey('alRefresh'), tooltip: tr(context, 'retry'), onPressed: _refresh, icon: const Icon(Icons.refresh_rounded))]),
      body: FutureBuilder<List<AdminAlert>>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) return ErrorState(error: snap.error, onRetry: _refresh);
          final list = snap.data;
          if (list == null) return const Center(child: CircularProgressIndicator());
          if (list.isEmpty) return EmptyState(icon: Icons.verified_outlined, title: tr(context, 'alNone'));
          return ListView(padding: const EdgeInsets.all(16), children: [
            for (final a in list)
              AppCard(
                key: ValueKey('alert_${a.id}'),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(a.level == AlertLevel.info ? Icons.info_outline_rounded : Icons.warning_amber_rounded, color: _color(a.level)),
                  title: Text(_text(a), style: TextStyle(fontWeight: FontWeight.w700, color: _color(a.level))),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    final w = _screenFor(a.area);
                    if (w != null) Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
                  },
                ),
              ),
            const SizedBox(height: 8),
            Text(tr(context, 'alFootnote'), style: TextStyle(color: AppColors.faint, fontSize: 12)),
          ]);
        },
      ),
    );
  }
}
