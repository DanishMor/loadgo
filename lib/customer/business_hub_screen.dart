import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import 'bulk_post_screen.dart';
import 'business_screen.dart';
import 'route_report_screen.dart';
import 'shipments_screen.dart';

/// Menu for the enterprise tools: business profile and branches, bulk post,
/// route/branch report and two-leg import/export shipments.
class BusinessHubScreen extends StatelessWidget {
  const BusinessHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void open(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'businessTools'))),
      body: ListView(children: [
        ListTile(
          key: const ValueKey('hubBusiness'),
          leading: const Icon(Icons.business_center_outlined),
          title: Text(tr(context, 'businessProfile')),
          subtitle: Text(tr(context, 'branches')),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => open(const BusinessScreen()),
        ),
        ListTile(
          key: const ValueKey('hubBulk'),
          leading: const Icon(Icons.playlist_add_rounded),
          title: Text(tr(context, 'bulkPost')),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => open(const BulkPostScreen()),
        ),
        ListTile(
          key: const ValueKey('hubReport'),
          leading: const Icon(Icons.table_chart_outlined),
          title: Text(tr(context, 'routeReport')),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => open(const RouteReportScreen()),
        ),
        ListTile(
          key: const ValueKey('hubShipments'),
          leading: const Icon(Icons.sync_alt_rounded),
          title: Text(tr(context, 'shipments')),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => open(const ShipmentsScreen()),
        ),
      ]),
    );
  }
}
