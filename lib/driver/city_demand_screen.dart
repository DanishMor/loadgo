import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/matching/city_demand.dart';
import '../core/models/load.dart';
import '../core/models/vehicle.dart';
import '../core/services/backend.dart';
import '../core/services/load_service.dart';
import '../core/services/vehicle_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';
import '../core/widgets/logistics_labels.dart';

/// Driver > City demand: how many open loads start in each city and which
/// vehicle types are asked for most. Types the driver owns are highlighted.
class CityDemandScreen extends StatefulWidget {
  /// Injectable for tests; defaults to the live open loads.
  final Stream<List<Load>>? loads;

  const CityDemandScreen({super.key, this.loads});

  @override
  State<CityDemandScreen> createState() => _CityDemandScreenState();
}

class _CityDemandScreenState extends State<CityDemandScreen> {
  late final Stream<List<Load>> _loads = (widget.loads ?? LoadService.watchOpen()).asBroadcastStream();
  late final Stream<List<Vehicle>> _vehicles = VehicleService.watchMine().asBroadcastStream();

  String _cityLabel(CityDemand d) => d.city == DemandSummary.otherLabel ? tr(context, 'cityOther') : d.city;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.background, title: Text(tr(context, 'cityDemand'))),
      body: SafeArea(
        child: LiveStream<List<Load>>(
          stream: () => _loads,
          builder: (context, loads) {
            final summary = DemandSummary.from(loads, excludeShipperId: Backend.uid);
            if (summary.totalLoads == 0) {
              return EmptyState(icon: Icons.insights_rounded, title: tr(context, 'noDemand'));
            }
            return StreamBuilder<List<Vehicle>>(
              stream: _vehicles,
              builder: (context, snap) {
                final mine = {for (final v in snap.data ?? const <Vehicle>[]) v.type};
                final maxType = summary.byType.values.first;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
                  children: [
                    Text(trf(context, 'demandTotal', {'n': summary.totalLoads}), style: TextStyle(color: AppColors.muted)),
                    const SizedBox(height: 16),
                    Text(tr(context, 'demandByType'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    for (final e in summary.byType.entries)
                      Padding(
                        key: ValueKey('type_${e.key}'),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(children: [
                          SizedBox(
                            width: 110,
                            child: Text(vehicleTypeLabel(context, e.key),
                                style: TextStyle(fontWeight: mine.contains(e.key) ? FontWeight.w800 : FontWeight.w500)),
                          ),
                          Expanded(child: LinearProgressIndicator(value: e.value / maxType, minHeight: 10, borderRadius: BorderRadius.circular(8))),
                          const SizedBox(width: 8),
                          Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.w800)),
                          if (mine.contains(e.key)) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.local_shipping_rounded, size: 16, color: AppColors.primary)),
                        ]),
                      ),
                    const SizedBox(height: 16),
                    Text(tr(context, 'demandByCity'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    for (final c in summary.cities)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: AppCard(
                          key: ValueKey('city_${c.city}'),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text(_cityLabel(c), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                              Text(trf(context, 'demandLoads', {'n': c.loads}), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
                            ]),
                            const SizedBox(height: 8),
                            Wrap(spacing: 8, runSpacing: 4, children: [
                              for (final t in c.byType.entries.take(4))
                                Chip(
                                  visualDensity: VisualDensity.compact,
                                  label: Text('${vehicleTypeLabel(context, t.key)} × ${t.value}'),
                                  backgroundColor: mine.contains(t.key) ? AppColors.primaryLight : null,
                                ),
                            ]),
                          ]),
                        ),
                      ),
                    Text(tr(context, 'demandNote'), style: TextStyle(color: AppColors.faint, fontSize: 12)),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
