import 'dart:async';

import 'package:flutter/material.dart';

import '../app_info.dart';
import '../location/live_location_sharer.dart';
import '../models/booking.dart';
import '../services/booking_service.dart';
import '../services/location_service.dart';
import 'common.dart';
import '../l10n/l10n.dart';
import '../theme/design_tokens.dart';
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

  bool get _live => LiveLocationSharer.enabled;

  @override
  void initState() {
    super.initState();
    if (_live) {
      // G11: the shared service keeps going when this screen is closed; it stops with the trip.
      LiveLocationSharer.start(widget.booking.id, noticeTitle: trf(context, 'liveNoticeTitle', {'app': AppInfo.name}), noticeText: tr(context, 'liveNoticeText'));
    } else {
      _start();
    }
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
    if (_live) {
      return ValueListenableBuilder<SharingState>(
        valueListenable: LiveLocationSharer.state,
        builder: (context, s, _) {
          final on = s == SharingState.on || s == SharingState.starting;
          final key = switch (s) {
            SharingState.noConsent => 'liveNoConsent',
            SharingState.noPermission => 'liveNoPermission',
            SharingState.off => 'locationSharingOff',
            _ => 'locationSharingOn',
          };
          return AppCard(
            child: Row(children: [
              Icon(on ? Icons.my_location_rounded : Icons.location_off_rounded, color: on ? AppColors.success : Colors.redAccent),
              const SizedBox(width: 12),
              Expanded(child: Text(trf(context, key, {'app': AppInfo.name}), key: const ValueKey('liveShareState'), style: DsStyle.w700.copyWith(color: AppColors.body))),
            ]),
          );
        },
      );
    }
    return AppCard(
      child: Row(
        children: [
          Icon(_denied ? Icons.location_off_rounded : Icons.my_location_rounded,
              color: _denied ? Colors.redAccent : AppColors.success),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tr(context, _denied ? 'locationSharingOff' : 'locationSharingOn'),
              style: DsStyle.w700.copyWith(color: AppColors.body),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Last seen 5 min ago" for the customer when no map is shown (G11).
String lastSeenText(BuildContext context, DateTime at, {DateTime? now}) {
  final m = (now ?? DateTime.now()).difference(at).inMinutes;
  if (m < 1) return tr(context, 'lastSeenNow');
  if (m < 120) return trf(context, 'lastSeenMinutes', {'n': m});
  return trf(context, 'lastSeenHours', {'n': m ~/ 60});
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
                Text(tr(context, 'driverLocation'), style: DsStyle.w700.copyWith(color: AppColors.title)),
                const SizedBox(height: 2),
                if (loc == null)
                  Text(tr(context, 'locationNotShared'), style: DsStyle.inherit.copyWith(color: AppColors.muted))
                else ...[
                  if (!LiveLocationSharer.enabled)
                      Text('${loc.latitude.toStringAsFixed(5)}, ${loc.longitude.toStringAsFixed(5)}',
                        style: DsStyle.w700.copyWith(color: AppColors.body)),
                  if (at != null)
                    Text(
                      LiveLocationSharer.enabled ? lastSeenText(context, at) : '${tr(context, 'updatedAt')}: ${formatDateTime(at)}',
                      key: const ValueKey('lastSeen'),
                      style: DsStyle.t12w400.copyWith(color: AppColors.muted),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
