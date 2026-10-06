import 'package:flutter/material.dart';

import '../core/enterprise/business_roles.dart';
import '../core/l10n/l10n.dart';
import '../core/services/business_service.dart';
import 'bulk_post_screen.dart';
import 'business_ops_screens.dart';
import 'business_screen.dart';
import 'business_statement_screen.dart';
import 'business_team_screen.dart';
import 'route_report_screen.dart';
import 'shipments_screen.dart';

/// Menu for the enterprise tools. What shows depends on the role the signed-in
/// user has in the company (owner, manager, dispatch, accounts, viewer, booker).
class BusinessHubScreen extends StatefulWidget {
  const BusinessHubScreen({super.key});

  @override
  State<BusinessHubScreen> createState() => _BusinessHubScreenState();
}

class _BusinessHubScreenState extends State<BusinessHubScreen> {
  late final Future<BizContext?> _ctx = BusinessService.myContext();

  @override
  Widget build(BuildContext context) {
    void open(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    Widget tile(String key, IconData icon, String title, Widget Function() screen, {String? subtitle}) => ListTile(
          key: ValueKey(key),
          leading: Icon(icon),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => open(screen()),
        );
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'businessTools'))),
      body: FutureBuilder<BizContext?>(
        future: _ctx,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          final c = snap.data;
          // No company yet: the profile screen is where one is created.
          final owner = c == null || c.isOwner;
          bool can(String perm) => c != null && c.can(perm);
          return ListView(children: [
            if (owner) tile('hubBusiness', Icons.business_center_outlined, tr(context, 'businessProfile'), () => const BusinessScreen(), subtitle: tr(context, 'branches')),
            if (owner) tile('hubTeam', Icons.groups_outlined, tr(context, 'businessTeam'), () => const BusinessTeamScreen(), subtitle: tr(context, 'teamRolePick')),
            if (c != null) ListTile(key: const ValueKey('hubRole'), leading: const Icon(Icons.badge_outlined), title: Text(bizRoleLabel(context, c.role))),
            if (owner || can(BizPerm.viewStatements))
              tile('hubStatement', Icons.receipt_long_outlined, tr(context, 'monthlyStatement'), () => BusinessStatementScreen(ownerId: c?.ownerId), subtitle: tr(context, 'byCostCenter')),
            if (c != null && c.can(BizPerm.approveLoads)) tile('hubApprovals', Icons.fact_check_outlined, tr(context, 'bizApprovals'), () => ApprovalsScreen(context: c)),
            if (c != null && (c.can(BizPerm.manageExpenses) || c.can(BizPerm.viewStatements))) tile('hubSpend', Icons.pie_chart_outline_rounded, tr(context, 'bizExpenses'), () => SpendDashboardScreen(context: c)),
            if (c != null) tile('hubContracts', Icons.local_shipping_outlined, tr(context, 'bizContracts'), () => ContractsScreen(context: c)),
            if (c != null && c.can(BizPerm.postLoads)) tile('hubPool', Icons.verified_user_outlined, tr(context, 'bizPool'), () => PoolScreen(context: c)),
            if (c != null && c.can(BizPerm.businessSupport)) tile('hubSupport', Icons.support_agent_rounded, tr(context, 'bizSupport'), () => BusinessSupportScreen(context: c)),
            if (owner || can(BizPerm.postLoads)) tile('hubBulk', Icons.playlist_add_rounded, tr(context, 'bulkPost'), () => const BulkPostScreen()),
            if (owner || can(BizPerm.viewBookings)) tile('hubReport', Icons.table_chart_outlined, tr(context, 'routeReport'), () => const RouteReportScreen()),
            if (owner) tile('hubShipments', Icons.sync_alt_rounded, tr(context, 'shipments'), () => const ShipmentsScreen()),
          ]);
        },
      ),
    );
  }
}
