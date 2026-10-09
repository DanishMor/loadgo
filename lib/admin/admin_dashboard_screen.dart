import 'admin_violations_screen.dart';
import 'package:flutter/material.dart';

import '../core/admin/staff_roles.dart';
import '../core/constants/logistics.dart';
import '../core/l10n/l10n.dart';
import '../core/services/admin_console_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';
import '../core/widgets/logistics_labels.dart';
import 'admin_assistant_screen.dart';
import 'admin_claims_screen.dart';
import 'admin_feedback_screen.dart';
import 'admin_demo_screen.dart';
import 'admin_features_screen.dart';
import 'admin_unit_economics_screen.dart';
import 'admin_pilot_funnel_screen.dart';
import 'admin_invites_screen.dart';
import 'admin_pilot_control_screen.dart';
import 'admin_dispatch_screen.dart';
import 'admin_pilot_report_screen.dart';
import 'admin_cohorts_screen.dart';
import 'admin_surveys_screen.dart';
import 'admin_payment_aging_screen.dart';
import 'admin_search_screen.dart';
import 'admin_alerts_screen.dart';
import 'admin_supply_demand_screen.dart';
import 'admin_health_screen.dart';
import 'admin_templates_screen.dart';
import 'admin_config_screen.dart';
import 'admin_driver_rewards_screen.dart';
import 'admin_fraud_cases_screen.dart';
import 'admin_rating_burst_screen.dart';
import 'admin_rating_flags_screen.dart';
import 'admin_trends_section.dart';
import 'admin_lists.dart';
import 'admin_offers_screen.dart';
import 'admin_payouts_screen.dart';
import 'admin_signals_screen.dart';
import 'admin_verification_screen.dart';
import 'flagged_users_screen.dart';

String staffRoleKey(String role) => switch (role) {
      StaffRole.support => 'staffRoleSupport',
      StaffRole.verifier => 'staffRoleVerifier',
      StaffRole.ops => 'staffRoleOps',
      StaffRole.finance => 'staffRoleFinance',
      _ => 'staffRoleSuper',
    };

/// Entry to every admin screen. Reached from the profile menu for admins.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late final Future<String> _role = AdminConsoleService.staffRole();

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
      ('pcAdminViolations', 'pcAdminViolations', Icons.gpp_maybe_outlined, const AdminViolationsScreen()),
      ('adminSignals', 'adminSignals', Icons.shield_outlined, const AdminSignalsScreen()),
      ('adminFraudCases', 'adminFraudCases', Icons.gavel_rounded, const AdminFraudCasesScreen()),
      ('adminDisputes', 'adminDisputes', Icons.report_problem_outlined, const AdminClaimsScreen()),
      ('adminRatingFlags', 'adminRatingFlags', Icons.star_half_rounded, const AdminRatingFlagsScreen()),
      ('adminRatingBurst', 'adminRatingBurst', Icons.star_border_purple500_rounded, const AdminRatingBurstScreen()),
      ('adminAssistant', 'adminAssistant', Icons.chat_bubble_outline_rounded, const AdminAssistantScreen()),
      ('adminFeedback', 'adminFeedback', Icons.rate_review_outlined, const AdminFeedbackScreen()),
      ('adminHealth', 'adminHealth', Icons.monitor_heart_outlined, const AdminHealthScreen()),
      ('adminTemplates', 'adminTemplates', Icons.quickreply_outlined, const AdminTemplatesScreen()),
      ('adminSupplyDemand', 'adminSupplyDemand', Icons.balance_rounded, const AdminSupplyDemandScreen()),
      ('adminPilotControl', 'adminPilotControl', Icons.dashboard_customize_outlined, const AdminPilotControlScreen()),
      ('adminAlerts', 'adminAlerts', Icons.notifications_active_outlined, const AdminAlertsScreen()),
      ('adminSearch', 'adminSearch', Icons.search_rounded, const AdminSearchScreen()),
      ('adminPayAging', 'adminPayAging', Icons.hourglass_bottom_rounded, const AdminPaymentAgingScreen()),
      ('adminSurveys', 'adminSurveys', Icons.thumbs_up_down_outlined, const AdminSurveysScreen()),
      ('adminCohorts', 'adminCohorts', Icons.query_stats_rounded, const AdminCohortsScreen()),
      ('adminPilotReport', 'adminPilotReport', Icons.summarize_outlined, const AdminPilotReportScreen()),
      ('adminDispatch', 'adminDispatch', Icons.alt_route_rounded, const AdminDispatchScreen()),
      ('adminWaitlist', 'adminWaitlist', Icons.hourglass_top_rounded, const AdminWaitlistScreen()),
      ('adminInvites', 'adminInvites', Icons.vpn_key_outlined, const AdminInvitesScreen()),
      ('adminPilotFunnel', 'adminPilotFunnel', Icons.filter_alt_outlined, const AdminPilotFunnelScreen()),
      ('adminUnitEconomics', 'adminUnitEconomics', Icons.calculate_outlined, const AdminUnitEconomicsScreen()),
      ('adminFeatures', 'adminFeatures', Icons.toggle_on_outlined, const AdminFeaturesScreen()),
      ('adminDemo', 'adminDemo', Icons.science_outlined, const AdminDemoScreen()),
      ('flaggedUsers', 'flaggedUsers', Icons.warning_amber_rounded, const FlaggedUsersScreen()),
      ('adminDeletionRequests', 'adminDeletionRequests', Icons.person_remove_outlined, const AdminDeletionRequestsScreen()),
      ('adminAudit', 'adminAudit', Icons.history_rounded, const AdminAuditScreen()),
      ('adminDriverRewards', 'adminDriverRewards', Icons.emoji_events_outlined, const AdminDriverRewardsScreen()),
      ('adminPayouts', 'adminPayouts', Icons.account_balance_outlined, const AdminPayoutsScreen()),
      ('adminOffers', 'adminOffers', Icons.local_offer_outlined, const AdminOffersScreen()),
      ('adminConfig', 'adminConfig', Icons.tune_rounded, const AdminConfigScreen()),
    ];
    return FutureBuilder<String>(
      future: _role,
      builder: (context, snap) {
        final role = snap.data;
        return Scaffold(
          appBar: AppBar(
            leading: BackButton(onPressed: () => Navigator.of(context, rootNavigator: true).maybePop()),
            title: Text(tr(context, 'adminPanel')),
            actions: [
              if (role != null)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(child: Text(tr(context, staffRoleKey(role)), key: const ValueKey('staffRole'), style: const TextStyle(fontSize: 12))),
                ),
            ],
          ),
          body: ListView(
            children: [
              for (final (key, label, icon, screen) in items)
                if (role == null || staffCan(role, key))
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
      },
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
  int _refresh = 0;

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
          IconButton(tooltip: tr(context, 'a11yRefresh'), 
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => setState(() {
              _future = AdminConsoleService.counters();
              _refresh++;
            }),
          ),
        ],
      ),
      body: FutureBuilder<AdminCounters>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return ErrorState(error: snap.error);
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
            const SizedBox(height: 20),
            AdminTrendsSection(key: ValueKey('trends_$_refresh')),
          ]);
        },
      ),
    );
  }
}
