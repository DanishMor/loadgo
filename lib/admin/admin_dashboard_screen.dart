import 'package:flutter/material.dart';

import '../core/constants/logistics.dart';
import '../core/l10n/l10n.dart';
import '../core/services/admin_console_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/logistics_labels.dart';
import 'admin_claims_screen.dart';
import 'admin_config_screen.dart';
import 'admin_driver_rewards_screen.dart';
import 'admin_fraud_cases_screen.dart';
import 'admin_rating_flags_screen.dart';
import 'admin_lists.dart';
import 'admin_offers_screen.dart';
import 'admin_payouts_screen.dart';
import 'admin_signals_screen.dart';
import 'admin_verification_screen.dart';
import 'flagged_users_screen.dart';

/// Entry to every admin screen. Reached from the profile menu for admins.
class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void open(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    final items = <(String, String, IconData, Widget)>[
      ('adminAnalytics', 'adminAnalytics', Icons.bar_chart_rounded, const AdminAnalyticsScreen()),
      ('adminUsers', 'adminUsers', Icons.people_alt_outlined, const AdminUsersScreen()),
      ('driverVerification', 'driverVerification', Icons.verified_user_outlined, const AdminVerificationScreen()),
      ('adminVehicles', 'adminVehicles', Icons.local_shipping_outlined, const AdminVehiclesScreen()),
      ('adminLoads', 'adminLoads', Icons.inventory_2_outlined, const AdminLoadsScreen()),
      ('adminBookings', 'adminBookings', Icons.receipt_long_outlined, const AdminBookingsScreen()),
      ('adminTickets', 'adminTickets', Icons.support_agent_rounded, const AdminTicketsScreen()),
      ('adminSos', 'adminSos', Icons.sos_rounded, const AdminSosScreen()),
      ('adminReports', 'adminReports', Icons.flag_outlined, const AdminReportsScreen()),
      ('adminSignals', 'adminSignals', Icons.shield_outlined, const AdminSignalsScreen()),
      ('adminFraudCases', 'adminFraudCases', Icons.gavel_rounded, const AdminFraudCasesScreen()),
      ('adminDisputes', 'adminDisputes', Icons.report_problem_outlined, const AdminClaimsScreen()),
      ('adminRatingFlags', 'adminRatingFlags', Icons.star_half_rounded, const AdminRatingFlagsScreen()),
      ('flaggedUsers', 'flaggedUsers', Icons.warning_amber_rounded, const FlaggedUsersScreen()),
      ('adminDeletionRequests', 'adminDeletionRequests', Icons.person_remove_outlined, const AdminDeletionRequestsScreen()),
      ('adminAudit', 'adminAudit', Icons.history_rounded, const AdminAuditScreen()),
      ('adminDriverRewards', 'adminDriverRewards', Icons.emoji_events_outlined, const AdminDriverRewardsScreen()),
      ('adminPayouts', 'adminPayouts', Icons.account_balance_outlined, const AdminPayoutsScreen()),
      ('adminOffers', 'adminOffers', Icons.local_offer_outlined, const AdminOffersScreen()),
      ('adminConfig', 'adminConfig', Icons.tune_rounded, const AdminConfigScreen()),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'adminPanel'))),
      body: ListView(
        children: [
          for (final (key, label, icon, screen) in items)
            ListTile(
              key: ValueKey('admin_$key'),
              leading: Icon(icon),
              title: Text(tr(context, label)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => open(screen),
            ),
        ],
      ),
    );
  }
}

String _loadStatusLabel(BuildContext context, String s) => tr(context, switch (s) {
      LoadStatus.matched => 'statusMatched',
      LoadStatus.closed => 'statusClosed',
      _ => 'statusOpen',
    });

/// Counters: users, loads/bookings by status, delivered fare sum.
class AdminAnalyticsScreen extends StatefulWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  State<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends State<AdminAnalyticsScreen> {
  late Future<AdminCounters> _future = AdminConsoleService.counters();

  Widget _section(String title, Map<String, int> rows, String Function(String) label) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (final e in rows.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Expanded(child: Text(label(e.key))),
                Text('${e.value}', key: ValueKey('count_${e.key}'), style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'adminAnalytics')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => setState(() => _future = AdminConsoleService.counters()),
          ),
        ],
      ),
      body: FutureBuilder<AdminCounters>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text(tr(context, 'somethingWrong')));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final c = snap.data!;
          return ListView(padding: const EdgeInsets.all(16), children: [
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${tr(context, 'adminTotalUsers')}: ${c.users}', key: const ValueKey('totalUsers')),
                Text('${tr(context, 'adminDriversCount')}: ${c.drivers}'),
                Text('${tr(context, 'adminDeliveredFare')}: ${formatPaise(c.deliveredFarePaise)}',
                    key: const ValueKey('deliveredFare'), style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
            ),
            const SizedBox(height: 12),
            _section(tr(context, 'adminLoadsByStatus'), c.loadsByStatus, (s) => _loadStatusLabel(context, s)),
            const SizedBox(height: 12),
            _section(tr(context, 'adminBookingsByStatus'), c.bookingsByStatus, (s) => bookingStatusLabel(context, s)),
          ]);
        },
      ),
    );
  }
}
