import 'package:flutter/material.dart';

import '../core/assistant/sahayak_screen.dart';
import '../core/l10n/l10n.dart';
import '../core/notifications/notifications_screen.dart';
import '../core/profile/profile_view.dart';
import 'fleet_analytics_screen.dart';
import 'fleet_dashboard.dart';
import 'fleet_drivers_screen.dart';
import 'fleet_vehicles_screen.dart';
import '../core/widgets/common.dart';

/// Fleet owner home: dashboard, vehicles, drivers, profile.
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
      const FleetDashboard(),
      const FleetVehiclesScreen(),
      const FleetDriversScreen(),
      const FleetAnalyticsScreen(),
      const ProfileView(isDriver: false),
    ];
    return Scaffold(
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
          NavigationDestination(icon: const Icon(Icons.local_shipping_outlined), selectedIcon: const Icon(Icons.local_shipping_rounded), label: tr(context, 'fleetVehicles')),
          NavigationDestination(icon: const Icon(Icons.people_outline_rounded), selectedIcon: const Icon(Icons.people_rounded), label: tr(context, 'fleetDrivers')),
          NavigationDestination(icon: const Icon(Icons.insights_outlined), selectedIcon: const Icon(Icons.insights_rounded), label: tr(context, 'fleetAnalytics')),
          NavigationDestination(icon: const Icon(Icons.person_outline_rounded), selectedIcon: const Icon(Icons.person_rounded), label: tr(context, 'profile')),
        ],
      ),
    );
  }
}
