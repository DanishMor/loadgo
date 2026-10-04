import 'package:flutter/material.dart';

import '../core/constants/ports.dart';
import '../core/l10n/l10n.dart';

String tradeHubKindLabel(BuildContext context, TradeHubKind k) => tr(context, switch (k) {
      TradeHubKind.port => 'hubPort',
      TradeHubKind.icd => 'hubIcd',
      TradeHubKind.cfs => 'placeCfs',
    });

/// Search sheet over ports, ICDs and CFS hubs. Returns the chosen hub.
Future<TradeHub?> pickTradeHub(BuildContext context) => showModalBottomSheet<TradeHub>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _HubSheet(),
    );

class _HubSheet extends StatefulWidget {
  const _HubSheet();

  @override
  State<_HubSheet> createState() => _HubSheetState();
}

class _HubSheetState extends State<_HubSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final hubs = searchHubs(_query);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              key: const ValueKey('hubSearch'),
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr(context, 'pickPortIcd')),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView(children: [
              for (final h in hubs)
                ListTile(
                  key: ValueKey('hub_${h.code}'),
                  leading: Icon(switch (h.kind) {
                    TradeHubKind.port => Icons.directions_boat_rounded,
                    TradeHubKind.icd => Icons.train_rounded,
                    TradeHubKind.cfs => Icons.inventory_rounded,
                  }),
                  title: Text(h.name),
                  subtitle: Text('${tradeHubKindLabel(context, h.kind)} · ${h.city}'),
                  onTap: () => Navigator.pop(context, h),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
