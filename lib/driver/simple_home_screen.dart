import 'package:flutter/material.dart';

import '../core/assistant/sahayak_screen.dart';
import '../core/l10n/l10n.dart';
import '../core/l10n/language_widgets.dart';
import '../core/models/booking.dart';
import '../core/models/ledger_entry.dart';
import '../core/models/payout.dart';
import '../core/services/booking_service.dart';
import '../core/services/load_service.dart';
import '../core/services/payment_service.dart';
import '../core/services/payout_service.dart';
import '../core/settings/help_screen.dart';
import '../core/settings/simple_mode.dart';
import '../core/widgets/booking_list_view.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';
import 'available_loads_view.dart';
import 'driver_trip_screen.dart';
import 'wallet_screen.dart';

/// Driver home in Simple Mode: four big icon buttons, at most three words
/// on each (strings `simpleFindLoads`, `simpleMyTrips`, `simpleMoney`,
/// `simpleHelp`).
class SimpleDriverHome extends StatelessWidget {
  const SimpleDriverHome({super.key});

  void _push(BuildContext context, Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  Widget _big(BuildContext context, {required Key key, required IconData icon, required String label, required Color color, required VoidCallback onTap}) => Expanded(
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Material(
            color: color,
            borderRadius: BorderRadius.circular(24),
            child: InkWell(
              key: key,
              borderRadius: BorderRadius.circular(24),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 56, color: Colors.white),
                    const SizedBox(height: 12),
                    Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
          child: Column(
            children: [
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SahayakButton(
                    role: 'driver',
                    actions: SahayakActions(
                      openBookings: () => _push(context, const SimpleTripsScreen()),
                      openNearbyLoads: () => _push(context, const SimpleLoadsScreen()),
                    ),
                  ),
                  IconButton(tooltip: tr(context, 'language'), onPressed: () => showLanguageSelector(context), icon: const Icon(Icons.language_rounded, size: 30)),
                ]),
              ),
              // Tall enough for large text: at least 190, growing with the labels.
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 190),
                child: IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _big(context,
                      key: const ValueKey('simpleFindLoads'),
                      icon: Icons.search_rounded,
                      label: tr(context, 'simpleFindLoads'),
                      color: const Color(0xFF1565C0),
                      onTap: () => _push(context, const SimpleLoadsScreen())),
                  _big(context,
                      key: const ValueKey('simpleMyTrips'),
                      icon: Icons.route_rounded,
                      label: tr(context, 'simpleMyTrips'),
                      color: const Color(0xFF2E7D32),
                      onTap: () => _push(context, const SimpleTripsScreen())),
                  ]),
                ),
              ),
              // Tall enough for large text: at least 190, growing with the labels.
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 190),
                child: IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _big(context,
                      key: const ValueKey('simpleMoney'),
                      icon: Icons.currency_rupee_rounded,
                      label: tr(context, 'simpleMoney'),
                      color: const Color(0xFFEF6C00),
                      onTap: () => _push(context, const SimpleMoneyScreen())),
                  _big(context,
                      key: const ValueKey('simpleHelp'),
                      icon: Icons.help_outline_rounded,
                      label: tr(context, 'simpleHelp'),
                      color: const Color(0xFF6A1B9A),
                      onTap: () => _push(context, const HelpScreen())),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              const SimpleModeSwitch(),
            ],
          ),
        ),
      ),
    );
  }
}

class SimpleLoadsScreen extends StatelessWidget {
  const SimpleLoadsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr(context, 'simpleFindLoads'))),
        body: AvailableLoadsView(
          loads: LoadService.watchOpenPage,
          nearby: LoadService.watchNearby,
          onAccepted: (id) => openDriverTrip(context, id),
        ),
      );
}

class SimpleTripsScreen extends StatelessWidget {
  const SimpleTripsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr(context, 'simpleMyTrips'))),
        body: BookingListView(
          title: tr(context, 'simpleMyTrips'),
          bookings: BookingService.watchForDriverPage,
          emptyTitle: tr(context, 'noTrips'),
          onOpen: (id) => openDriverTrip(context, id),
        ),
      );
}

/// Balance and what can be requested, in one big line each.
class SimpleMoneyScreen extends StatelessWidget {
  const SimpleMoneyScreen({super.key});

  Widget _line(BuildContext context, String label, int paise, Color color, Key key) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 18, color: AppColors.muted)),
          Text(formatPaise(paise), key: key, style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: color)),
        ]),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr(context, 'simpleMoney'))),
        body: SafeArea(
          child: LiveStream<List<LedgerEntry>>(
            stream: PaymentService.watchLedger,
            builder: (context, entries) => LiveStream<List<Booking>>(
              stream: BookingService.watchForDriver,
              compact: true,
              builder: (context, bookings) => LiveStream<List<Payout>>(
                stream: PayoutService.watchMine,
                compact: true,
                builder: (context, payouts) {
                  final bal = WalletBalances.of(ledger: entries, bookings: bookings, payouts: payouts);
                  return ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _line(context, tr(context, 'simpleBalance'), bal.net, AppColors.title, const ValueKey('simpleBalance')),
                      _line(context, tr(context, 'simpleCanRequest'), bal.available, AppColors.success, const ValueKey('simpleAvailable')),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 64,
                        child: FilledButton.icon(
                          key: const ValueKey('simpleAskMoney'),
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalletScreen())),
                          icon: const Icon(Icons.account_balance_outlined, size: 28),
                          label: Text(tr(context, 'simpleAskMoney'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
}
