import 'package:flutter/material.dart';

import '../../core/models/booking.dart';
import '../../core/models/load.dart';
import '../../core/services/booking_service.dart';
import '../../core/models/vehicle.dart';
import '../../core/services/load_service.dart';
import '../../core/services/user_service.dart';
import '../../core/services/vehicle_service.dart';
import '../../core/widgets/common.dart';
import '../../main.dart';
import '../bookings/booking_list_view.dart';
import '../bookings/driver_trip_screen.dart';
import '../loads/available_loads_view.dart';
import '../loads/load_card.dart';
import '../notifications/notifications_screen.dart';
import '../profile/profile_view.dart';
import '../vehicle/my_vehicles_screen.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  static const _loadsTab = 1;

  int _index = 0;
  bool _isOnline = false;
  final Stream<List<Vehicle>> _vehicles = VehicleService.watchMine();
  final Stream<List<Load>> _homeOpenLoads = LoadService.watchOpen();
  final Stream<List<Load>> _tabOpenLoads = LoadService.watchOpen();
  final Stream<List<Booking>> _homeTrips = BookingService.watchForDriver();
  final Stream<List<Booking>> _tabTrips = BookingService.watchForDriver();

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _logout() async {
    await UserService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
      (route) => false,
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return tr(context, 'goodMorning');
    if (h < 17) return tr(context, 'goodAfternoon');
    return tr(context, 'goodEvening');
  }

  Widget _title(String text) => Text(text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF111827)));

  Widget _emptyCard(IconData icon, String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE4E7EC))),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF98A2B3)),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: const TextStyle(color: Color(0xFF667085)))),
          ],
        ),
      );

  Widget _tile(IconData icon, String label, {VoidCallback? onTap}) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap ?? () => _snack(tr(context, 'comingSoon')),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE4E7EC))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: const Color(0xFF1565C0), size: 28),
                const SizedBox(height: 10),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      );

  /// Up to three open loads on the home tab; the Loads tab shows the rest.
  Widget _homeLoads() {
    return StreamBuilder<List<Load>>(
      stream: _homeOpenLoads,
      builder: (context, snap) {
        if (snap.hasError) return StreamErrorText(snap.error);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final loads = snap.data!;
        if (loads.isEmpty) return _emptyCard(Icons.inventory_2_outlined, tr(context, 'noAvailableLoads'));
        return Column(
          children: [
            for (final load in loads.take(3)) ...[
              LoadCard(key: ValueKey(load.id), load: load, action: AcceptLoadButton(load: load, onAccepted: _onAccepted)),
              const SizedBox(height: 12),
            ],
            if (loads.length > 3)
              TextButton(onPressed: () => setState(() => _index = _loadsTab), child: Text(tr(context, 'viewAll'))),
          ],
        );
      },
    );
  }

  void _onAccepted(String bookingId) => openDriverTrip(context, bookingId);

  /// Nudges drivers without any vehicle to add one; hidden otherwise.
  Widget _noVehiclePrompt() {
    return StreamBuilder<List<Vehicle>>(
      stream: _vehicles,
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.isNotEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: AppCard(
            child: Row(
              children: [
                const Icon(Icons.local_shipping_rounded, color: AppColors.warning, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(context, 'noVehicleTitle'), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.title)),
                      const SizedBox(height: 2),
                      Text(tr(context, 'noVehicleSub'), style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => openAddVehicle(context, prefillFromProfile: true),
                  child: Text(tr(context, 'addVehicle')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _homeTab() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_greeting(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(tr(context, 'driver'), style: const TextStyle(color: Color(0xFF667085))),
                    ],
                  ),
                ),
                IconButton(onPressed: () => showLanguageSelector(context), icon: const Icon(Icons.language_rounded), color: const Color(0xFF1565C0)),
                NotificationBell(onOpenBooking: (id) => openDriverTrip(context, id)),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(color: _isOnline ? const Color(0xFFE7F8EF) : const Color(0xFFF2F4F7), borderRadius: BorderRadius.circular(18)),
              child: Row(
                children: [
                  Icon(Icons.circle, size: 14, color: _isOnline ? const Color(0xFF12B76A) : const Color(0xFF98A2B3)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_isOnline ? tr(context, 'online') : tr(context, 'offline'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                  Switch(value: _isOnline, onChanged: (v) => setState(() => _isOnline = v)),
                ],
              ),
            ),
            _noVehiclePrompt(),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF0D47A1), Color(0xFF1976D2)]), borderRadius: BorderRadius.circular(20)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(context, 'todayEarnings'), style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 6),
                  const Text('₹ 0', style: TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _title(tr(context, 'activeTrip')),
            const SizedBox(height: 12),
            ActiveTripCard(
              bookings: _homeTrips,
              onOpen: (id) => openDriverTrip(context, id),
              empty: _emptyCard(Icons.route_rounded, tr(context, 'noActiveTrip')),
            ),
            const SizedBox(height: 24),
            _title(tr(context, 'availableLoads')),
            const SizedBox(height: 12),
            _isOnline ? _homeLoads() : _emptyCard(Icons.wifi_off_rounded, tr(context, 'goOnlineToSee')),
            const SizedBox(height: 24),
            Row(
              children: [
                _tile(
                  Icons.local_shipping_rounded,
                  tr(context, 'myTruck'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyVehiclesScreen())),
                ),
                const SizedBox(width: 12),
                _tile(Icons.verified_user_rounded, tr(context, 'documentsKyc')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(IconData icon, String title, {bool withLogout = false}) {
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: const Color(0xFF1565C0)),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(tr(context, 'comingSoon'), style: const TextStyle(color: Color(0xFF1565C0))),
            if (withLogout) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(onPressed: _logout, icon: const Icon(Icons.logout_rounded), label: Text(tr(context, 'logout'))),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _homeTab(),
      AvailableLoadsView(loads: _tabOpenLoads, onAccepted: _onAccepted),
      BookingListView(
        title: tr(context, 'trips'),
        bookings: _tabTrips,
        emptyTitle: tr(context, 'noTrips'),
        onOpen: (id) => openDriverTrip(context, id),
      ),
      _placeholder(Icons.account_balance_wallet_rounded, tr(context, 'earnings')),
      const ProfileView(isDriver: true),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFE8F1FF),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home_rounded), label: tr(context, 'home')),
          NavigationDestination(icon: const Icon(Icons.inventory_2_outlined), selectedIcon: const Icon(Icons.inventory_2_rounded), label: tr(context, 'loads')),
          NavigationDestination(icon: const Icon(Icons.route_outlined), selectedIcon: const Icon(Icons.route_rounded), label: tr(context, 'trips')),
          NavigationDestination(icon: const Icon(Icons.account_balance_wallet_outlined), selectedIcon: const Icon(Icons.account_balance_wallet_rounded), label: tr(context, 'earnings')),
          NavigationDestination(icon: const Icon(Icons.person_outline_rounded), selectedIcon: const Icon(Icons.person_rounded), label: tr(context, 'profile')),
        ],
      ),
    );
  }
}