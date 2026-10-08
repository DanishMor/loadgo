import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import 'fleet_drivers_screen.dart';
import 'fleet_vehicles_screen.dart';

/// The fleet tab: vehicles (own and attached) and drivers.
class TransporterFleetScreen extends StatelessWidget {
  const TransporterFleetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        TabBar(tabs: [Tab(text: tr(context, 'fleetVehicles')), Tab(text: tr(context, 'fleetDrivers'))]),
        const Expanded(child: TabBarView(children: [FleetVehiclesScreen(), FleetDriversScreen()])),
      ]),
    );
  }
}
