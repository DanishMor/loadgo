import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/profile/profile_nav_tile.dart';
import 'business_hub_screen.dart';
import '../core/wallet/txn_history_screen.dart';
import 'my_drivers_screen.dart';
import 'templates_screen.dart';
import 'business_invites_card.dart';
import 'offers_screen.dart';
import 'truck_board_screen.dart';
import '../core/widgets/reminder_widgets.dart';
import '../core/reminders/reminders.dart';
import 'customer_analytics_screen.dart';

import '../core/services/auth_helpers.dart';
import '../core/services/booking_service.dart';
import '../core/l10n/l10n.dart';
import '../core/l10n/language_widgets.dart';
import 'booking_tracking_screen.dart';
import 'customer_bookings_view.dart';
import '../core/documents/invoice_screen.dart';
import 'my_loads_view.dart';
import '../core/notifications/notifications_screen.dart';
import 'post_load_screen.dart';
import '../core/profile/profile_view.dart';
import '../core/documents/documents_center_screen.dart';

// ============================================================
// CUSTOMER HOME DASHBOARD
// ============================================================

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  static const _bookingsTab = 1;
  static const _loadsTab = 2;

  int _currentIndex = 0;

  Future<void> _postLoad() async {
    final posted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const PostLoadScreen()),
    );
    // Show the freshly posted load in "My Loads".
    if (posted == true && mounted) setState(() => _currentIndex = _loadsTab);
  }

  void _openTab(int index) => setState(() => _currentIndex = index);

  void _openBooking(String bookingId) => openBookingTracking(context, bookingId);

  late final List<Widget> _pages = [
    _CustomerHomeContent(onPostLoad: _postLoad, onOpenTab: _openTab),
    CustomerBookingsView(
      bookings: BookingService.watchForCustomerPage,
      onOpenTracking: _openBooking,
      onOpenInvoice: (id) => openInvoice(context, id),
    ),
    MyLoadsView(onPostLoad: _postLoad, onOpenBooking: _openBooking),
    ProfileView(isDriver: false, extraTiles: [
      ProfileNavTile(
        key: const ValueKey('profileAnalytics'),
        icon: Icons.bar_chart_rounded,
        titleKey: 'myAnalytics',
        screen: (_) => const CustomerAnalyticsScreen(),
      ),
      ProfileNavTile(
        key: const ValueKey('profileOffers'),
        icon: Icons.local_offer_outlined,
        titleKey: 'offersAndCredits',
        screen: (_) => const OffersScreen(),
      ),
      ProfileNavTile(
        key: const ValueKey('profileBusiness'),
        icon: Icons.business_center_outlined,
        titleKey: 'businessTools',
        screen: (_) => const BusinessHubScreen(),
      ),
      ProfileNavTile(
        key: const ValueKey('profileTransactions'),
        icon: Icons.account_balance_wallet_outlined,
        titleKey: 'txnTitle',
        screen: (_) => const TxnHistoryScreen(isDriver: false),
      ),
      ProfileNavTile(
        key: const ValueKey('profileTemplates'),
        icon: Icons.bookmarks_outlined,
        titleKey: 'templatesTitle',
        screen: (_) => const TemplatesScreen(),
      ),
      ProfileNavTile(
        key: const ValueKey('profileMyDrivers'),
        icon: Icons.favorite_border_rounded,
        titleKey: 'favouriteDrivers',
        screen: (_) => const MyDriversScreen(),
      ),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFE8F1FF),
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home_rounded),
              label: tr(context, 'home')),
          NavigationDestination(
              icon: const Icon(Icons.receipt_long_outlined),
              selectedIcon: const Icon(Icons.receipt_long_rounded),
              label: tr(context, 'bookings')),
          NavigationDestination(
              icon: const Icon(Icons.inventory_2_outlined),
              selectedIcon: const Icon(Icons.inventory_2_rounded),
              label: tr(context, 'loads')),
          NavigationDestination(
              icon: const Icon(Icons.person_outline_rounded),
              selectedIcon: const Icon(Icons.person_rounded),
              label: tr(context, 'profile')),
        ],
      ),
    );
  }
}

// ============================================================
// HOME CONTENT
// ============================================================

class _CustomerHomeContent extends StatelessWidget {
  final VoidCallback onPostLoad;
  final ValueChanged<int> onOpenTab;

  const _CustomerHomeContent({required this.onPostLoad, required this.onOpenTab});

  static const _loadsTabIndex = 2;

  /// Pickup reminders open the booking; offers and "no driver yet" go to My Loads.
  void _openReminder(BuildContext context, Reminder r) {
    if ((r.kind == ReminderKind.pickupSoon || r.kind == ReminderKind.tripDelayed) && r.relatedId != null) {
      openBookingTracking(context, r.relatedId!);
    } else {
      onOpenTab(_loadsTabIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final phone = user?.phoneNumber ?? '';
    final displayPhone = phone.isNotEmpty ? maskPhone(phone) : tr(context, 'customer');

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: const Color(0xFFE8F1FF), borderRadius: BorderRadius.circular(15)),
                  child: const Icon(Icons.person_rounded, color: Color(0xFF1565C0), size: 27),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(context, 'welcomeBack'), style: const TextStyle(fontSize: 13, color: Color(0xFF667085))),
                      const SizedBox(height: 3),
                      Text(
                        displayPhone,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF111827)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: const Color(0xFFE4E7EC)),
                  ),
                  child: IconButton(
                    onPressed: () => showLanguageSelector(context),
                    icon: const Icon(Icons.language_rounded),
                    color: const Color(0xFF1565C0),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: const Color(0xFFE4E7EC)),
                  ),
                  child: NotificationBell(onOpenBooking: (id) => openBookingTracking(context, id)),
                ),
              ],
            ),
            const SizedBox(height: 25),
            Container(
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE4E7EC)),
              ),
              child: TextField(
                decoration: InputDecoration(
                  border: InputBorder.none,
                  prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF667085)),
                  hintText: tr(context, 'search'),
                  hintStyle: const TextStyle(color: Color(0xFF98A2B3), fontSize: 14),
                ), inputFormatters: [LengthLimitingTextInputFormatter(100)]),
            ),
            RemindersBanner(isDriver: false, onOpen: (r) => _openReminder(context, r)),
            const BusinessInvitesCard(),
            const SizedBox(height: 25),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(context, 'heroTitle'),
                    style: const TextStyle(color: Colors.white, fontSize: 26, height: 1.15, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    tr(context, 'heroSub'),
                    style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.45),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: onPostLoad,
                      icon: const Icon(Icons.local_shipping_rounded, size: 20),
                      label: Text(tr(context, 'bookTruck'), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF1565C0),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Text(tr(context, 'quickActions'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF111827))),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _QuickActionCard(
                    icon: Icons.local_shipping_rounded,
                    title: tr(context, 'bookTruck'),
                    subtitle: tr(context, 'findVehicle'),
                    onTap: onPostLoad,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _QuickActionCard(
                    icon: Icons.add_box_rounded,
                    title: tr(context, 'postLoad'),
                    subtitle: tr(context, 'findTransporter'),
                    onTap: onPostLoad,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _QuickActionCard(
                    icon: Icons.location_on_rounded,
                    title: tr(context, 'track'),
                    subtitle: tr(context, 'trackShipment'),
                    onTap: () => onOpenTab(_CustomerHomeScreenState._bookingsTab),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _QuickActionCard(
                    icon: Icons.folder_copy_outlined,
                    title: tr(context, 'documentsCenter'),
                    subtitle: tr(context, 'invoice'),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const DocumentsCenterScreen(asDriver: false))),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _QuickActionCard(
                    icon: Icons.local_shipping_outlined,
                    title: tr(context, 'emptyTrucks'),
                    subtitle: tr(context, 'emptyTrucksSub'),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TruckBoardScreen())),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(child: SizedBox.shrink()),
              ],
            ),
            const SizedBox(height: 28),
            Text(tr(context, 'services'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF111827))),
            const SizedBox(height: 14),
            SizedBox(
              height: 128,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _ServiceCard(icon: Icons.fire_truck_rounded, title: tr(context, 'fullTruck'), subtitle: tr(context, 'ftl')),
                  _ServiceCard(icon: Icons.local_shipping_rounded, title: tr(context, 'container'), subtitle: tr(context, 'importExport')),
                  _ServiceCard(icon: Icons.agriculture_rounded, title: tr(context, 'agriLoad'), subtitle: tr(context, 'agricultural')),
                  _ServiceCard(icon: Icons.inventory_2_rounded, title: tr(context, 'generalCargo'), subtitle: tr(context, 'allCargo')),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(tr(context, 'recent'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF111827))),
                TextButton(
                  onPressed: () {},
                  child: Text(tr(context, 'viewAll'), style: const TextStyle(color: Color(0xFF1565C0), fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE4E7EC)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(color: const Color(0xFFF2F4F7), borderRadius: BorderRadius.circular(18)),
                    child: const Icon(Icons.inbox_outlined, size: 30, color: Color(0xFF667085)),
                  ),
                  const SizedBox(height: 12),
                  Text(tr(context, 'noActivity'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF344054))),
                  const SizedBox(height: 5),
                  Text(
                    tr(context, 'activitySub'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF98A2B3)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// QUICK ACTION CARD
// ============================================================

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickActionCard({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE4E7EC)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: const Color(0xFFE8F1FF), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: const Color(0xFF1565C0), size: 25),
            ),
            const SizedBox(height: 12),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF111827))),
            const SizedBox(height: 3),
            Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Color(0xFF667085))),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SERVICE CARD
// ============================================================

class _ServiceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _ServiceCard({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 145,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF1565C0), size: 32),
          const Spacer(),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF111827))),
          const SizedBox(height: 3),
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Color(0xFF667085))),
        ],
      ),
    );
  }
}
