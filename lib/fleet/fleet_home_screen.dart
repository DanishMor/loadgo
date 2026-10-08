import '../core/call/call_screens.dart';
import 'package:flutter/material.dart';

import '../core/assistant/sahayak_screen.dart';
import '../core/l10n/l10n.dart';
import '../core/notifications/notifications_screen.dart';
import '../core/profile/profile_view.dart';
import 'fleet_dashboard.dart';
import 'transporter_fleet_screen.dart';
import 'transporter_loads_screen.dart';
import 'transporter_shortcuts.dart';
import 'transporter_trips_screen.dart';
import '../core/widgets/common.dart';

/// Transporter home: dashboard, vehicles, drivers, profile.
class FleetHomeScreen extends StatefulWidget {
  const FleetHomeScreen({super.key});

  @override
  State<FleetHomeScreen> createState() => _FleetHomeScreenState();
}

class _FleetHomeScreenState extends State<FleetHomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const FleetDashboard(header: TransporterShortcuts()),
      const TransporterLoadsScreen(),
      const TransporterTripsScreen(),
      const TransporterFleetScreen(),
      const ProfileView(isDriver: false),
    ];
    return IncomingCallHost(
      child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: _index == 4
          ? null
          : AppBar(
              backgroundColor: AppColors.background,
              scrolledUnderElevation: 0,
              automaticallyImplyLeading: false,
              title: Text(tr(context, 'fleetOwner'), style: const TextStyle(fontWeight: FontWeight.w800)),
              actions: [const SahayakButton(role: 'fleet', actions: SahayakActions()), NotificationBell(onOpenBooking: (_) {})],
            ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.dashboard_outlined), selectedIcon: const Icon(Icons.dashboard_rounded), label: tr(context, 'fleetDashboard')),
          NavigationDestination(icon: const Icon(Icons.inventory_2_outlined), selectedIcon: const Icon(Icons.inventory_2_rounded), label: tr(context, 'trpTabLoads')),
          NavigationDestination(icon: const Icon(Icons.route_outlined), selectedIcon: const Icon(Icons.route_rounded), label: tr(context, 'trpTabTrips')),
          NavigationDestination(icon: const Icon(Icons.local_shipping_outlined), selectedIcon: const Icon(Icons.local_shipping_rounded), label: tr(context, 'trpTabFleet')),
          NavigationDestination(icon: const Icon(Icons.person_outline_rounded), selectedIcon: const Icon(Icons.person_rounded), label: tr(context, 'profile')),
        ],
      ),
    ),
    );
  }
}
