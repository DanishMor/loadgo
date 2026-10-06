import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n/l10n.dart';
import '../core/models/booking.dart';
import '../core/models/load.dart';
import '../core/search/text_search.dart';
import '../core/services/booking_service.dart';
import '../core/services/load_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/load_card.dart';
import 'booking_tracking_screen.dart';

/// Home search: the customer's own loads and bookings by place, goods,
/// vehicle, driver or status words ("del mum" finds Delhi to Mumbai).
class HomeSearchScreen extends StatefulWidget {
  final String initialQuery;
  final Stream<List<Load>>? loads;
  final Stream<List<Booking>>? bookings;

  const HomeSearchScreen({super.key, this.initialQuery = '', this.loads, this.bookings});

  @override
  State<HomeSearchScreen> createState() => _HomeSearchScreenState();
}

class _HomeSearchScreenState extends State<HomeSearchScreen> {
  late final _ctrl = TextEditingController(text: widget.initialQuery);
  late final Stream<List<Load>> _loads = (widget.loads ?? LoadService.watchMine()).asBroadcastStream();
  late final Stream<List<Booking>> _bookings = (widget.bookings ?? BookingService.watchForCustomer()).asBroadcastStream();
  List<Load> _myLoads = const [];
  List<Booking> _myBookings = const [];

  @override
  void initState() {
    super.initState();
    _loads.listen((l) => mounted ? setState(() => _myLoads = l) : null, onError: (_) {});
    _bookings.listen((b) => mounted ? setState(() => _myBookings = b) : null, onError: (_) {});
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  static List<String?> loadFields(Load l) => [l.pickup, l.drop, ...l.extraPickups, ...l.extraDrops, l.cargoType, l.vehicleType, l.notes, l.status];
  static List<String?> bookingFields(Booking b) => [b.pickup, b.drop, b.cargoType, b.vehicleType, b.driverName, b.vehicleNumber, b.status];

  @override
  Widget build(BuildContext context) {
    final q = _ctrl.text;
    final loads = [for (final l in _myLoads) if (matchesQuery(q, loadFields(l))) l];
    final bookings = [for (final b in _myBookings) if (matchesQuery(q, bookingFields(b))) b];
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          key: const ValueKey('homeSearchField'),
          controller: _ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: tr(context, 'search'), border: InputBorder.none, filled: false),
          inputFormatters: [LengthLimitingTextInputFormatter(60)],
          onChanged: (_) => setState(() {}),
        ),
      ),
      body: q.trim().isEmpty
          ? const SizedBox.shrink()
          : (loads.isEmpty && bookings.isEmpty)
              ? EmptyState(icon: Icons.search_off_rounded, title: trf(context, 'searchNoResults', {'q': q.trim()}))
              : ListView(padding: const EdgeInsets.all(16), children: [
                  if (bookings.isNotEmpty) ...[
                    Text(tr(context, 'searchBookingsHeader'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 8),
                    for (final b in bookings)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: AppCard(
                          key: ValueKey('hitBooking_${b.id}'),
                          onTap: () => openBookingTracking(context, b.id),
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.local_shipping_rounded),
                            title: Text('${b.pickup} → ${b.drop}'),
                            subtitle: Text('${b.cargoType} · ${b.driverName}'),
                          ),
                        ),
                      ),
                  ],
                  if (loads.isNotEmpty) ...[
                    Text(tr(context, 'searchLoadsHeader'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 8),
                    for (final l in loads) Padding(padding: const EdgeInsets.only(bottom: 8), child: LoadCard(key: ValueKey('hitLoad_${l.id}'), load: l, showStatus: true)),
                  ],
                ]),
    );
  }
}
