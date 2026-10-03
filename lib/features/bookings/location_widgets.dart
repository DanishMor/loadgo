import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/booking.dart';
import '../../core/services/booking_service.dart';
import '../../core/services/location_service.dart';
import '../../core/widgets/common.dart';
import '../../main.dart';

/// Minimum gap between Firestore writes so sharing stays lightweight.
const _minWriteGap = Duration(seconds: 15);

/// Driver side: while mounted (the trip is in transit) publishes the device
/// position to the booking. Renders a small status card.
class LocationSharingCard extends StatefulWidget {
  final Booking booking;
  final Duration minWriteGap;

  const LocationSharingCard({super.key, required this.booking, this.minWriteGap = _minWriteGap});

  @override
  State<LocationSharingCard> createState() => _LocationSharingCardState();
}

class _LocationSharingCardState extends State<LocationSharingCard> {
  StreamSubscription<Coordinates>? _sub;
  DateTime? _lastWrite;
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final ok = await LocationService.ensurePermission();
    if (!mounted) return;
    if (!ok) {
      setState(() => _denied = true);
      return;
    }
    _sub = LocationService.positions().listen(_onPosition, onError: (_) {
      if (mounted) setState(() => _denied = true);
    });
  }

  Future<void> _onPosition(Coordinates c) async {
    final now = DateTime.now();
    if (_lastWrite != null && now.difference(_lastWrite!) < widget.minWriteGap) return;
    _lastWrite = now;
    try {
      await BookingService.updateLocation(widget.booking.id, c.lat, c.lng);
    } catch (_) {
      // Best effort: the next position update retries.
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Icon(_denied ? Icons.location_off_rounded : Icons.my_location_rounded,
              color: _denied ? Colors.redAccent : AppColors.success),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tr(context, _denied ? 'locationSharingOff' : 'locationSharingOn'),
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.body),
            ),
          ),
        ],
      ),
    );
  }
}

/// Customer side: the driver's last known position as text (until a map key
/// is configured, see docs/MANUAL_SETUP.md).
class DriverLocationCard extends StatelessWidget {
  final Booking booking;

  const DriverLocationCard({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    final loc = booking.lastKnownLocation;
    final at = booking.locationUpdatedAt;
    return AppCard(
      child: Row(
        children: [
          const Icon(Icons.location_on_rounded, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(context, 'driverLocation'), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.title)),
                const SizedBox(height: 2),
                if (loc == null)
                  Text(tr(context, 'locationNotShared'), style: const TextStyle(color: AppColors.muted))
                else ...[
                  Text('${loc.latitude.toStringAsFixed(5)}, ${loc.longitude.toStringAsFixed(5)}',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.body)),
                  if (at != null)
                    Text('${tr(context, 'updatedAt')}: ${formatDateTime(at)}',
                        style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
