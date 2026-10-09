import '../core/errors/error_text.dart';
import 'package:flutter/material.dart';

import '../core/constants/logistics.dart';
import '../core/documents/lr_screen.dart';
import '../core/l10n/l10n.dart';
import '../core/models/booking.dart';
import '../core/models/fleet.dart';
import '../core/models/offer.dart';
import '../core/models/vehicle.dart';
import '../core/navigation/app_routes.dart';
import '../core/services/fleet_service.dart';
import '../core/services/offer_service.dart';
import '../core/services/pricing_service.dart';
import '../core/services/transporter_service.dart';
import '../core/services/vehicle_service.dart';
import '../core/transporter/transporter_logic.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';
import '../core/widgets/logistics_labels.dart';
import 'transporter_books_screen.dart';

/// Trips of the company: my bids (confirm a selected one), late-trip alerts,
/// and every trip with its status, assigned vehicle and driver (assign or
/// reassign before loading ends), LR / bilty and the books line.
class TransporterTripsScreen extends StatefulWidget {
  /// Injectable for tests.
  final Stream<List<Booking>>? bookings;
  final Stream<List<Offer>>? offers;
  final Stream<List<FleetMember>>? members;
  final Future<List<Vehicle>> Function()? vehicles;
  final DateTime Function() now;

  const TransporterTripsScreen({super.key, this.bookings, this.offers, this.members, this.vehicles, this.now = DateTime.now});

  @override
  State<TransporterTripsScreen> createState() => _TransporterTripsScreenState();
}

class _TransporterTripsScreenState extends State<TransporterTripsScreen> {
  late final Stream<List<Booking>> _bookings = (widget.bookings ?? FleetService.watchFleetBookings()).asBroadcastStream();
  late final Stream<List<Offer>> _offers = (widget.offers ?? OfferService.watchMine()).asBroadcastStream();
  late final Stream<List<FleetMember>> _members = (widget.members ?? FleetService.watchMembers()).asBroadcastStream();

  Future<List<Vehicle>> _fleetVehicles() async {
    if (widget.vehicles != null) return widget.vehicles!();
    final own = await VehicleService.fetchMyActive();
    final attached = await TransporterService.watchAttached().first;
    return {for (final v in [...own, ...attached]) v.id: v}.values.toList();
  }

  String _released = '';

  /// Free the vehicles of finished company trips (once per change).
  void _release(List<Booking> bookings) {
    if (widget.bookings != null) return;
    final sig = [for (final b in bookings) if (b.isCompanyBooking) '${b.id}:${b.status}'].join(',');
    if (sig == _released) return;
    _released = sig;
    TransporterService.releaseFinished(bookings);
  }

  Future<void> _confirm(Offer o) async {
    try {
      await OfferService.confirm(o);
      if (mounted) showSnack(context, tr(context, 'trpJobConfirmed'));
    } on OfferStateException {
      if (mounted) showSnack(context, tr(context, 'offerChanged'));
    } catch (error) {
      if (mounted) showSnack(context, errorText(context, error));
    }
  }

  Future<void> _assign(Booking b) async {
    final members = [for (final m in await _members.first) if (m.active) m];
    final vehicles = await _fleetVehicles();
    if (!mounted) return;
    if (members.isEmpty) return showSnack(context, tr(context, 'trpNoDrivers'));
    var driver = members.firstWhere((m) => m.driverId == b.assignedDriverId, orElse: () => members.first);
    final currentVehicle = b.assignedVehicleId ?? b.vehicleId;
    var vehicle = vehicles.firstWhere((v) => v.id == currentVehicle, orElse: () => vehicles.isEmpty ? Vehicle(id: '', ownerId: '', number: '', type: '', capacity: 0, rcNumber: '', status: '') : vehicles.first);
    if (vehicles.isEmpty) return showSnack(context, tr(context, 'trpNoVehicle'));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: Text(tr(c, b.assignedDriverId == null ? 'trpAssign' : 'trpReassign')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              key: const ValueKey('assignDriver'),
              isExpanded: true,
              initialValue: driver.driverId,
              decoration: InputDecoration(labelText: tr(c, 'trpPickDriver')),
              items: [for (final m in members) DropdownMenuItem(value: m.driverId, child: Text(m.driverName.isEmpty ? m.driverId : m.driverName))],
              onChanged: (v) => setS(() => driver = members.firstWhere((m) => m.driverId == v)),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: const ValueKey('assignVehicle'),
              isExpanded: true,
              initialValue: vehicle.id,
              decoration: InputDecoration(labelText: tr(c, 'trpPickVehicle')),
              items: [for (final v in vehicles) DropdownMenuItem(value: v.id, child: Text('${v.number} • ${vehicleTypeLabel(c, v.type)}'))],
              onChanged: (v) => setS(() => vehicle = vehicles.firstWhere((x) => x.id == v)),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr(c, 'cancel'))),
            FilledButton(key: const ValueKey('assignSave'), onPressed: () => Navigator.pop(c, true), child: Text(tr(c, 'save'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await TransporterService.assign(booking: b, vehicle: vehicle, driver: driver, now: widget.now());
      if (mounted) showSnack(context, tr(context, 'trpAssigned'));
    } on AssignException catch (e) {
      if (mounted) showSnack(context, tr(context, 'trpErr_${e.reason}'));
    } catch (error) {
      if (mounted) showSnack(context, errorText(context, error));
    }
  }

  Widget _bids(BuildContext context, List<Offer> offers) {
    final mine = [for (final o in offers) if (o.isCompanyBid && (o.isOpen || o.status == OfferStatus.rejected)) o];
    if (mine.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        key: const ValueKey('trpBids'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(context, 'trpMyBids'), style: const TextStyle(fontWeight: FontWeight.w800)),
          for (final o in mine)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${o.pickup} → ${o.drop}', style: const TextStyle(fontWeight: FontWeight.w700)),
                Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(formatPaise(o.pricePaise), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
                  StatusChip(label: offerStatusLabel(context, o.status), color: offerStatusColor(o.status)),
                  if (o.status == OfferStatus.selected) FilledButton(key: ValueKey('trpConfirm_${o.id}'), onPressed: () => _confirm(o), child: Text(tr(context, 'trpConfirmJob'))),
                ]),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _late(BuildContext context, List<Booking> bookings) {
    final alerts = DelayAlert.compute(bookings, widget.now(), (b) => PricingService.estimateRouteKm(b.route));
    if (alerts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        key: const ValueKey('trpLate'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.schedule_rounded, color: AppColors.warning),
            const SizedBox(width: 8),
            Expanded(child: Text(tr(context, 'trpDelayTitle'), style: const TextStyle(fontWeight: FontWeight.w800))),
          ]),
          for (final a in alerts)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('${a.booking.pickup} → ${a.booking.drop}: ${trf(context, 'trpDelay', {'m': a.minutesLate})}', key: ValueKey('late_${a.booking.id}')),
            ),
        ]),
      ),
    );
  }

  Widget _trip(BuildContext context, Booking b) {
    final canChange = b.isCompanyBooking && [BookingStatus.accepted, BookingStatus.driverArriving, BookingStatus.loading].contains(b.status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        key: ValueKey('trpTrip_${b.id}'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${b.pickup} → ${b.drop}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          StatusChip(label: bookingStatusLabel(context, b.status), color: bookingStatusColor(b.status)),
          const SizedBox(height: 2),
          Text('${b.cargoType} • ${formatNum(b.weight)} T${b.billAmountPaise == null ? '' : ' • ${formatPaise(b.billAmountPaise!)}'}', style: TextStyle(color: AppColors.muted)),
          if (b.isCompanyBooking)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                b.assignedDriverId == null
                    ? tr(context, 'trpNotAssigned')
                    : trf(context, 'trpAssignedTo', {'driver': b.assignedDriverName, 'vehicle': b.assignedVehicleNumber}),
                key: ValueKey('trpAssignedLine_${b.id}'),
                style: TextStyle(color: b.assignedDriverId == null ? AppColors.warning : AppColors.title, fontWeight: FontWeight.w600),
              ),
            ),
          Wrap(spacing: 4, children: [
            if (canChange)
              TextButton.icon(
                key: ValueKey('trpAssign_${b.id}'),
                onPressed: () => _assign(b),
                icon: const Icon(Icons.assignment_ind_outlined, size: 18),
                label: Text(tr(context, b.assignedDriverId == null ? 'trpAssign' : 'trpReassign')),
              ),
            TextButton.icon(
              key: ValueKey('trpLr_${b.id}'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LrScreen(bookingId: b.id))),
              icon: const Icon(Icons.description_outlined, size: 18),
              label: Text(tr(context, 'trpLr')),
            ),
            if (b.isCompanyBooking)
              TextButton.icon(
                key: ValueKey('trpBooksButton_${b.id}'),
                onPressed: () => editTripAccount(context, b),
                icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                label: Text(tr(context, 'trpBooks')),
              ),
            if (b.isCompanyBooking && AppRoutes.openBooking != null)
              TextButton(onPressed: () => AppRoutes.openBooking!(context, b.id, isDriver: true), child: Text(tr(context, 'tripDetails'))),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LiveStream<List<Booking>>(
      stream: () => _bookings,
      builder: (context, bookings) => LiveStream<List<Offer>>(
        stream: () => _offers,
        compact: true,
        builder: (context, offers) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _release(bookings));
          final bids = _bids(context, offers);
          if (bookings.isEmpty && bids is SizedBox) return EmptyState(icon: Icons.route_outlined, title: tr(context, 'trpNoTrips'));
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
            bids,
            _late(context, bookings),
            for (final b in bookings) _trip(context, b),
          ]);
        },
      ),
    );
  }
}
