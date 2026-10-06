import 'dart:async';

import 'package:flutter/material.dart';

import '../core/geo/trip_watcher.dart';
import '../core/l10n/l10n.dart';
import '../core/models/app_notification.dart';
import '../core/models/booking.dart';
import '../core/services/location_service.dart';
import '../core/services/notification_service.dart';
import '../core/trip/trip_alerts.dart';
import '../core/widgets/common.dart';

/// Position samples for the driver's trip widgets: the injected stream in
/// tests, the device position otherwise (nothing without permission).
Future<Stream<Coordinates>?> _positionsOrNull(Stream<Coordinates>? injected) async {
  if (injected != null) return injected;
  if (!await LocationService.ensurePermission()) return null;
  return LocationService.positions();
}

/// While the driver is on the way to the pickup: "about N km to pickup" and
/// "you are at the pickup" (T3), and one in-app notification to the customer
/// once the driver is within [arrivingAlertKm] (N2). In-app only; a push
/// message needs an FCM sender (LATER(paid)).
class PickupGeofenceBanner extends StatefulWidget {
  final Booking booking;
  final Stream<Coordinates>? positions;
  final DateTime Function() now;
  const PickupGeofenceBanner({super.key, required this.booking, this.positions, this.now = DateTime.now});

  @override
  State<PickupGeofenceBanner> createState() => _PickupGeofenceBannerState();
}

class _PickupGeofenceBannerState extends State<PickupGeofenceBanner> {
  late final TripWatcher _watcher = TripWatcher(dropPlace: widget.booking.pickup);
  StreamSubscription<Coordinates>? _sub;
  TripSignals _signals = const TripSignals();
  bool _alerted = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final stream = await _positionsOrNull(widget.positions);
    if (stream == null || !mounted) return;
    _sub = stream.listen((p) {
      _watcher.add(widget.now(), p.lat, p.lng);
      final s = _watcher.signals(widget.now());
      if (mounted) setState(() => _signals = s);
      final km = s.kmToDrop;
      if (!_alerted && km != null && km <= arrivingAlertKm) {
        _alerted = true;
        NotificationService.sendOnce(
          id: 'arrive_${widget.booking.id}',
          userId: widget.booking.customerId,
          type: NotificationType.arrivingSoon,
          message: '${widget.booking.pickup} → ${widget.booking.drop}',
          relatedId: widget.booking.id,
        ).catchError((_) {});
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _signals;
    if (s.kmToDrop == null) return const SizedBox.shrink();
    final reached = s.destinationReached;
    return AppCard(
      key: ValueKey(reached ? 'pickupReached' : 'pickupNear'),
      child: Row(children: [
        Icon(reached ? Icons.flag_circle_outlined : Icons.near_me_rounded, color: reached ? AppColors.success : AppColors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            reached ? tr(context, 'geoPickupReached') : trf(context, 'geoPickupNear', {'km': s.kmToDrop!.round()}),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ]),
    );
  }
}

/// Progress through the drops of a multi-stop trip (T7): each stop turns
/// reached when the phone is within a few km of it, with an alert line for
/// the stop just reached and the next stop's distance.
class StopProgressCard extends StatefulWidget {
  final Booking booking;
  final Stream<Coordinates>? positions;
  const StopProgressCard({super.key, required this.booking, this.positions});

  @override
  State<StopProgressCard> createState() => _StopProgressCardState();
}

class _StopProgressCardState extends State<StopProgressCard> {
  late final List<String> _stops = [...widget.booking.extraDrops, widget.booking.drop];
  late final StopTracker _tracker = StopTracker(_stops);
  StreamSubscription<Coordinates>? _sub;
  int? _justReached;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final stream = await _positionsOrNull(widget.positions);
    if (stream == null || !mounted) return;
    _sub = stream.listen((p) {
      final fresh = _tracker.add(p.lat, p.lng);
      if (mounted) setState(() => _justReached = fresh.isEmpty ? _justReached : fresh.last);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_stops.length < 2) return const SizedBox.shrink();
    final next = _tracker.nextIndex;
    final km = _tracker.kmToNext;
    return AppCard(
      key: const ValueKey('stopProgress'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(trf(context, 'stopsProgress', {'done': _tracker.reachedCount, 'total': _stops.length}), style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (var i = 0; i < _stops.length; i++)
          Row(children: [
            Icon(_tracker.reached(i) ? Icons.check_circle_rounded : (i == next ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded),
                size: 18, color: _tracker.reached(i) ? AppColors.success : (i == next ? AppColors.primary : AppColors.faint)),
            const SizedBox(width: 8),
            Expanded(child: Text(_stops[i], key: ValueKey('stop_$i'))),
          ]),
        if (_justReached != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(trf(context, 'stopReachedAlert', {'place': _stops[_justReached!]}), key: const ValueKey('stopAlert'), style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w700)),
          ),
        if (next != null && km != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(trf(context, 'stopNext', {'place': _stops[next], 'km': km.round()}), style: TextStyle(color: AppColors.muted)),
          ),
      ]),
    );
  }
}
