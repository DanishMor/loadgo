import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/enterprise/route_report.dart';
import '../core/l10n/l10n.dart';
import '../core/services/enterprise_service.dart';
import '../core/widgets/common.dart';

/// Loads, deliveries and spend per route and per branch, with CSV copy.
class RouteReportScreen extends StatelessWidget {
  const RouteReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'routeReport'))),
      body: FutureBuilder<RouteReport>(
        future: EnterpriseService.routeReport(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text(tr(context, 'somethingWrong')));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final r = snap.data!;
          String line(int loads, int delivered, int spend) =>
              trf(context, 'reportRowText', {'loads': loads, 'delivered': delivered, 'spend': formatPaise(spend)});
          return ListView(padding: const EdgeInsets.all(16), children: [
            OutlinedButton.icon(
              key: const ValueKey('copyCsv'),
              icon: const Icon(Icons.copy_rounded),
              label: Text(tr(context, 'copyCsv')),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: r.toCsv()));
                if (context.mounted) showSnack(context, tr(context, 'copied'));
              },
            ),
            const SizedBox(height: 16),
            Text(tr(context, 'reportByRoute'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            if (r.routes.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(tr(context, 'statNoData'))),
            for (final x in r.routes)
              ListTile(
                key: ValueKey('routeRow_${x.route}'),
                contentPadding: EdgeInsets.zero,
                title: Text(x.route),
                subtitle: Text(line(x.loads, x.delivered, x.spendPaise)),
              ),
            const SizedBox(height: 16),
            Text(tr(context, 'reportByBranch'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            if (r.branches.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(tr(context, 'statNoData'))),
            for (final x in r.branches)
              ListTile(
                key: ValueKey('branchRow_${x.branch}'),
                contentPadding: EdgeInsets.zero,
                title: Text(x.branch),
                subtitle: Text(line(x.loads, x.delivered, x.spendPaise)),
              ),
          ]);
        },
      ),
    );
  }
}
