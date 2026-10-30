import 'package:flutter/material.dart';

import '../../core/assistant/sahayak_screen.dart';
import '../../core/dispatch/auto_accept_watcher.dart';
import '../../core/documents/documents_center_screen.dart';
import '../../core/features/features.dart';
import '../../core/l10n/l10n.dart';
import '../../core/navigation/deep_links.dart';
import '../../core/services/features_service.dart';
import '../../core/settings/help_screen.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/vehicles/vehicle_catalog.dart';
import '../../core/vehicles/vehicle_screens.dart';
import '../../core/widgets/common.dart';
import '../booking_tracking_screen.dart';
import '../business_hub_screen.dart';
import '../customer_home_screen.dart' show customerProfileView;
import '../offers_screen.dart';
import '../spending_screen.dart';
import '../templates_screen.dart';
import '../truck_board_screen.dart';
import '../v3/customer_home_v3.dart';
import 'bid_room_screen.dart';
import 'booking_wizard_model.dart';
import 'booking_wizard_screen.dart';
import 'customer_home_v2.dart';
import 'trips_tab_v2.dart';

/// U18: the new customer app (switch `uiV2`): Home, Trips, Help and Profile in a bottom bar. Booking opens the
/// five-step wizard; a posted load opens the Bid Room. The old home stays in the code and comes back with `uiV2` off.
class CustomerShellV2 extends StatefulWidget {
  const CustomerShellV2({super.key});

  @override
  State<CustomerShellV2> createState() => _CustomerShellV2State();
}

class _CustomerShellV2State extends State<CustomerShellV2> {
  static const _tripsTab = 1;
  int _index = 0;

  late final SahayakActions _sahayak = SahayakActions(
    openBookings: () => setState(() => _index = _tripsTab),
    openPostLoad: (prefill) => _bookFrom(WizardDraft(pickup: prefill['pickup'] ?? '', drop: prefill['drop'] ?? '', vehicleType: prefill['vehicleType'])),
  );

  Future<void> _wizard(WizardDraft? draft) async {
    final id = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => BookWizardScreen(initial: draft)));
    if (id == null || !mounted) return;
    if (id == 'schedule') return _wizard(const WizardDraft());
    await _openLoad(id);
    if (mounted) setState(() => _index = 0);
  }

  Future<void> _book() => _wizard(null);

  Future<void> _bookFrom(WizardDraft d) => _wizard(d);

  Future<void> _openLoad(String id) async {
    final r = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => BidRoomScreen(loadId: id)));
    if (r == 'schedule' && mounted) await _wizard(const WizardDraft());
  }

  void _openBooking(String id) => openBookingTracking(context, id);

  void _push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  Widget _tile(IconData icon, String title, VoidCallback onTap, {Key? key}) {
    final c = context.ds;
    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpace.s2),
      child: AppCard(
        key: key,
        onTap: onTap,
        child: Row(children: [
          Icon(icon, color: c.primary),
          const SizedBox(width: DsSpace.s3),
          Expanded(child: Text(title, style: DsType.subtitle.copyWith(color: c.textStrong))),
          const Icon(Icons.chevron_right_rounded),
        ]),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    AutoAcceptWatcher.start();
    FeaturesService.notifier.addListener(AutoAcceptWatcher.start);
  }

  @override
  void dispose() {
    FeaturesService.notifier.removeListener(AutoAcceptWatcher.start);
    AutoAcceptWatcher.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      ValueListenableBuilder<Features>(
        valueListenable: FeaturesService.notifier,
        builder: (context, f, _) {
          final more = [
            _tile(Icons.folder_copy_outlined, tr(context, 'documentsCenter'), () => _push(const DocumentsCenterScreen(asDriver: false)), key: const ValueKey('moreDocs')),
            if (f.isOn(FeatureKey.emptyTrucks)) _tile(Icons.local_shipping_outlined, tr(context, 'emptyTrucks'), () => _push(const TruckBoardScreen()), key: const ValueKey('moreTrucks')),
            _tile(Icons.two_wheeler_rounded, tr(context, 'bookBike'), () => _bookFrom(const WizardDraft(vehicleType: 'Bike')), key: const ValueKey('moreBike')),
            if (f.isOn(FeatureKey.businessTools)) _tile(Icons.business_center_outlined, tr(context, 'businessTools'), () => _push(const BusinessHubScreen()), key: const ValueKey('moreBusiness')),
            _tile(Icons.bookmarks_outlined, tr(context, 'templatesTitle'), () => _push(const TemplatesScreen()), key: const ValueKey('moreTemplates')),
            _tile(Icons.savings_outlined, tr(context, 'ehSpendTitle'), () => _push(const SpendingScreen()), key: const ValueKey('moreSpending')),
          ];
          // E21: the arrangeable home (homeV3 needs the Signature look, designV3).
          if (f.isOn(FeatureKey.homeV3) && f.isOn(FeatureKey.designV3)) {
            return CustomerHomeV3(
              onBook: _book,
              onBookFrom: _bookFrom,
              onOpenBooking: _openBooking,
              onOpenLoad: _openLoad,
              onOpenTrips: () => setState(() => _index = _tripsTab),
              onOpenOffers: () => _push(const OffersScreen()),
              onOpenCatalog: () => _push(VehicleCatalogScreen(onPick: (VehicleSpec spec) {
                Navigator.of(context).pop();
                _bookFrom(WizardDraft(vehicleType: spec.legacyId));
              })),
              onOpenTemplates: () => _push(const TemplatesScreen()),
              sahayak: _sahayak,
              more: more,
            );
          }
          return CustomerHomeV2(
            onBook: _book,
            onBookFrom: _bookFrom,
            onOpenBooking: _openBooking,
            onOpenLoad: _openLoad,
            onOpenTrips: () => setState(() => _index = _tripsTab),
            sahayak: _sahayak,
            more: more,
          );
        },
      ),
      TripsTabV2(onOpenBooking: _openBooking, onOpenLoad: _openLoad, onBookAgain: (item) => _bookFrom(item.toDraft()), onBook: _book),
      const HelpScreen(role: 'customer'),
      customerProfileView(),
    ];
    return DeepLinkListener(
      isDriver: false,
      child: Scaffold(
        body: IndexedStack(index: _index, children: pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home_rounded), label: tr(context, 'hvTabHome')),
            NavigationDestination(icon: const Icon(Icons.receipt_long_outlined), selectedIcon: const Icon(Icons.receipt_long_rounded), label: tr(context, 'hvTabTrips')),
            NavigationDestination(icon: const Icon(Icons.support_agent_outlined), selectedIcon: const Icon(Icons.support_agent_rounded), label: tr(context, 'hvTabHelp')),
            NavigationDestination(icon: const Icon(Icons.person_outline_rounded), selectedIcon: const Icon(Icons.person_rounded), label: tr(context, 'hvTabProfile')),
          ],
        ),
      ),
    );
  }
}
