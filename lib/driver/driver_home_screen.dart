import '../core/assistant/sahayak_screen.dart';
import '../core/search/global_search_screen.dart';
import '../core/network/network_screen.dart';
import 'package:flutter/material.dart';

import '../core/profile/profile_nav_tile.dart';
import '../auth/driver_kyc_screen.dart';
import 'driver_analytics_screen.dart';

import '../core/models/booking.dart';
import '../core/models/load.dart';
import '../core/services/booking_service.dart';
import '../core/models/vehicle.dart';
import '../core/matching/load_ranker.dart';
import '../core/services/load_service.dart';
import '../core/services/match_service.dart';
import '../core/services/user_service.dart';
import '../core/services/vehicle_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/kyc_check_widgets.dart';
import '../core/l10n/l10n.dart';
import '../core/l10n/language_widgets.dart';
import '../core/widgets/booking_list_view.dart';
import 'driver_location_sync.dart';
import 'driver_trip_screen.dart';
import '../core/settings/simple_mode.dart';
import 'simple_home_screen.dart';
import '../core/reminders/reminders.dart';
import '../core/widgets/reminder_widgets.dart';
import 'city_demand_screen.dart';
import 'upcoming_trips.dart';
import 'empty_trucks_screen.dart';
import 'earnings_view.dart';
import 'available_loads_view.dart';
import '../core/widgets/load_card.dart';
import '../core/notifications/notifications_screen.dart';
import '../core/profile/profile_view.dart';
import '../core/widgets/live_stream.dart';
import 'my_vehicles_screen.dart';
import 'vehicle_alerts_banner.dart';
import 'doc_suspension_banner.dart';
import '../core/services/doc_expiry_service.dart';
import 'my_offers_screen.dart';
import 'fleet_invites_card.dart';
import 'wallet_screen.dart';
import '../core/documents/documents_center_screen.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  static const _loadsTab = 1;
  static const _tripsTab = 2;

  int _index = 0;
  bool _isOnline = false;
  final Stream<List<Vehicle>> _vehicles = VehicleService.watchMine().asBroadcastStream();
  final Stream<List<Booking>> _todayTrips = BookingService.watchForDriver();
  final Stream<List<Load>> _openLoads = LoadService.watchOpen().asBroadcastStream();
  final Stream<List<FavouriteRoute>> _favourites = MatchService.watchFavourites().asBroadcastStream();
  DateTime? _loadsSeenAt;
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    DriverLocationSync.refresh();
    DocExpiryService.syncMine().catchError((_) => 0);
    UserService.getUser().then((u) {
      if (!mounted) return;
      setState(() {
        _profile = u;
        if (u?['online'] == true) _isOnline = true;
      });
    }).catchError((_) {});
    MatchService.lastSeenLoads().then((t) {
      if (!mounted) return;
      if (t != null) {
        setState(() => _loadsSeenAt = t);
      } else {
        // First run: nothing counts as new until the driver looks once.
        _markLoadsSeen();
      }
    });
  }

  void _markLoadsSeen() {
    final now = DateTime.now();
    MatchService.markLoadsSeen(now);
    setState(() => _loadsSeenAt = now);
  }

  void _selectTab(int i) {
    setState(() => _index = i);
    if (i == _loadsTab) _markLoadsSeen();
  }

  /// Loads tab icon with a count of loads posted since the driver last looked.
  Widget _loadsIcon(IconData icon) {
    return StreamBuilder<List<FavouriteRoute>>(
      stream: _favourites,
      builder: (context, favs) => StreamBuilder<List<Load>>(
        stream: _openLoads,
        builder: (context, snap) {
          final n = _index == _loadsTab
              ? 0
              : LoadRanker.countNew(snap.data ?? const [], _loadsSeenAt, favourites: favs.data ?? const []);
          return Badge(
            key: const ValueKey('newLoadsBadge'),
            isLabelVisible: n > 0,
            label: Text(n > 9 ? '9+' : '$n'),
            child: Icon(icon),
          );
        },
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return tr(context, 'goodMorning');
    if (h < 17) return tr(context, 'goodAfternoon');
    return tr(context, 'goodEvening');
  }

  Widget _title(String text) => Text(text, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.title));

  Widget _emptyCard(IconData icon, String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.border)),
        child: Row(
          children: [
            Icon(icon, color: AppColors.faint),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: TextStyle(color: AppColors.muted))),
          ],
        ),
      );

  Widget _tile(IconData icon, String label, {VoidCallback? onTap}) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap ?? () => _snack(tr(context, 'comingSoon')),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.border)),
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
    return LiveStream<List<Load>>(
      stream: LoadService.watchOpen,
      compact: true,
      builder: (context, loads) {
        if (loads.isEmpty) return _emptyCard(Icons.inventory_2_outlined, tr(context, 'noAvailableLoads'));
        return Column(
          children: [
            for (final load in loads.take(3)) ...[
              LoadCard(key: ValueKey(load.id), load: load, networkShare: true, action: AcceptLoadButton(load: load, onAccepted: _onAccepted)),
              const SizedBox(height: 12),
            ],
            if (loads.length > 3)
              TextButton(onPressed: () => _selectTab(_loadsTab), child: Text(tr(context, 'viewAll'))),
          ],
        );
      },
    );
  }

  Future<void> _setOnline(bool v) async {
    setState(() => _isOnline = v);
    try {
      await UserService.setOnline(v);
    } catch (_) {
      // Offline: the switch still works for this session.
    }
  }

  /// Pickup reminders open the trip, offer reminders My Offers, papers My Truck.
  void _openReminder(Reminder r) {
    switch (r.kind) {
      case ReminderKind.pickupSoon || ReminderKind.tripDelayed || ReminderKind.rateTrip:
        if (r.relatedId != null) openDriverTrip(context, r.relatedId!);
      case ReminderKind.counterWaiting || ReminderKind.confirmWaiting:
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MyOffersScreen(onOpenBooking: (id) => openDriverTrip(context, id)),
        ));
      default:
        _openVehicles();
    }
  }

  void _openVehicles() =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyVehiclesScreen()));

  void _openLicence() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DriverKycScreen(edit: true)));

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
                      Text(tr(context, 'noVehicleTitle'), style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.title)),
                      const SizedBox(height: 2),
                      Text(tr(context, 'noVehicleSub'), style: TextStyle(fontSize: 12, color: AppColors.muted)),
                    ],
                  ),
                ),
                Flexible(
                  child: TextButton(
                    onPressed: () => openAddVehicle(context, prefillFromProfile: true),
                    child: Text(tr(context, 'addVehicle'), textAlign: TextAlign.center),
                  ),
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
                      Text(tr(context, 'driver'), style: TextStyle(color: AppColors.muted)),
                    ],
                  ),
                ),
                IconButton(
                  key: const ValueKey('driverSearch'),
                  tooltip: tr(context, 'search'),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GlobalSearchScreen(isDriver: true))),
                  icon: const Icon(Icons.search_rounded),
                  color: const Color(0xFF1565C0),
                ),
                SahayakButton(
                  role: 'driver',
                  actions: SahayakActions(
                    openBookings: () => _selectTab(_tripsTab),
                    openNearbyLoads: () => _selectTab(_loadsTab),
                  ),
                ),
                IconButton(tooltip: tr(context, 'language'), onPressed: () => showLanguageSelector(context), icon: const Icon(Icons.language_rounded), color: const Color(0xFF1565C0)),
                NotificationBell(isDriver: true, onOpenBooking: (id) => openDriverTrip(context, id)),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(color: _isOnline ? const Color(0xFFE7F8EF) : AppColors.chip, borderRadius: BorderRadius.circular(18)),
              child: Row(
                children: [
                  Icon(Icons.circle, size: 14, color: _isOnline ? const Color(0xFF12B76A) : AppColors.faint),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_isOnline ? tr(context, 'online') : tr(context, 'offline'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                  Switch(key: const ValueKey('onlineSwitch'), value: _isOnline, onChanged: _setOnline),
                ],
              ),
            ),
            const SimpleModePrompt(),
            _noVehiclePrompt(),
            const ReviewFlagBanner(),
            RemindersBanner(isDriver: true, onOpen: _openReminder),
            UpcomingTripsCard(onOpen: (id) => openDriverTrip(context, id)),
            DocSuspensionBanner(vehicles: _vehicles, profile: _profile, onOpenVehicles: _openVehicles, onOpenLicence: _openLicence),
            VehicleAlertsBanner(vehicles: _vehicles, onTap: _openVehicles),
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
                  TodayEarningsText(bookings: _todayTrips),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _title(tr(context, 'activeTrip')),
            const SizedBox(height: 12),
            ActiveTripCard(
              bookings: BookingService.watchForDriver,
              onOpen: (id) => openDriverTrip(context, id),
              empty: _emptyCard(Icons.route_rounded, tr(context, 'noActiveTrip')),
            ),
            const SizedBox(height: 24),
            _title(tr(context, 'availableLoads')),
            const SizedBox(height: 12),
            const FleetInvitesCard(),
            _isOnline ? _homeLoads() : _emptyCard(Icons.wifi_off_rounded, tr(context, 'goOnlineToSee')),
            const SizedBox(height: 24),
            Row(
              children: [
                _tile(Icons.local_shipping_rounded, tr(context, 'myTruck'), onTap: _openVehicles),
                const SizedBox(width: 12),
                _tile(Icons.verified_user_rounded, tr(context, 'documentsKyc'), onTap: _openVehicles),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _tile(
                  Icons.insights_rounded,
                  tr(context, 'cityDemand'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CityDemandScreen())),
                ),
                const SizedBox(width: 12),
                _tile(
                  Icons.local_shipping_outlined,
                  tr(context, 'emptyTrucks'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EmptyTrucksScreen())),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _tile(
                  Icons.local_offer_outlined,
                  tr(context, 'myOffers'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => MyOffersScreen(onOpenBooking: (id) => openDriverTrip(context, id)),
                  )),
                ),
                const SizedBox(width: 12),
                _tile(
                  Icons.account_balance_wallet_outlined,
                  tr(context, 'wallet'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalletScreen())),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _tile(
                  Icons.folder_copy_outlined,
                  tr(context, 'documentsCenter'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => DocumentsCenterScreen(
                      asDriver: true,
                      header: OutlinedButton.icon(
                        onPressed: _openVehicles,
                        icon: const Icon(Icons.assignment_outlined),
                        label: Text(tr(context, 'vehiclePapers')),
                      ),
                    ),
                  )),
                ),
                const SizedBox(width: 12),
                const Spacer(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: SimpleMode.notifier,
        builder: (context, simple, _) => simple ? const SimpleDriverHome() : _fullHome(context),
      );

  Widget _fullHome(BuildContext context) {
    final pages = [
      _homeTab(),
      AvailableLoadsView(loads: LoadService.watchOpenPage, nearby: LoadService.watchNearby, onAccepted: _onAccepted),
      BookingListView(
        title: tr(context, 'trips'),
        bookings: BookingService.watchForDriverPage,
        emptyTitle: tr(context, 'noTrips'),
        onOpen: (id) => openDriverTrip(context, id),
      ),
      EarningsView(bookings: BookingService.watchForDriver, onOpenTrip: (id) => openDriverTrip(context, id)),
      ProfileView(isDriver: true, extraTiles: [
        ProfileNavTile(
          key: const ValueKey('profileAnalytics'),
          icon: Icons.bar_chart_rounded,
          titleKey: 'myAnalytics',
          screen: (_) => const DriverAnalyticsScreen(),
        ),
        ProfileNavTile(
          key: const ValueKey('profileNetwork'),
          icon: Icons.groups_2_outlined,
          titleKey: 'netTitle',
          screen: (_) => const NetworkScreen(),
        ),
        ProfileNavTile(
          key: const ValueKey('profileEditDocuments'),
          icon: Icons.badge_outlined,
          titleKey: 'editDocuments',
          screen: (_) => const DriverKycScreen(edit: true),
        ),
      ]),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _selectTab,
        backgroundColor: AppColors.card,
        indicatorColor: AppColors.primaryLight,
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home_rounded), label: tr(context, 'home')),
          NavigationDestination(icon: _loadsIcon(Icons.inventory_2_outlined), selectedIcon: const Icon(Icons.inventory_2_rounded), label: tr(context, 'loads')),
          NavigationDestination(icon: const Icon(Icons.route_outlined), selectedIcon: const Icon(Icons.route_rounded), label: tr(context, 'trips')),
          NavigationDestination(icon: const Icon(Icons.account_balance_wallet_outlined), selectedIcon: const Icon(Icons.account_balance_wallet_rounded), label: tr(context, 'earnings')),
          NavigationDestination(icon: const Icon(Icons.person_outline_rounded), selectedIcon: const Icon(Icons.person_rounded), label: tr(context, 'profile')),
        ],
      ),
    );
  }
}