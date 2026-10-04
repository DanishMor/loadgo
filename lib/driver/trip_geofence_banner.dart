import 'dart:async';

import 'package:flutter/material.dart';

import '../core/geo/trip_watcher.dart';
import '../core/l10n/l10n.dart';
import '../core/services/location_service.dart';
import '../core/widgets/common.dart';

/// Shown on the driver's trip while in transit: near the drop, drop reached
/// and long halt alerts, worked out from the phone's position (in-app only).
class TripGeofenceBanner extends StatefulWidget {
  final String dropPlace;

  /// Injectable for tests; defaults to the device position stream.
  final Stream<Coordinates>? positions;
  final DateTime Function() now;

  const TripGeofenceBanner({super.key, required this.dropPlace, this.positions, this.now = DateTime.now});

  @override
  State<TripGeofenceBanner> createState() => _TripGeofenceBannerState();
}

class _TripGeofenceBannerState extends State<TripGeofenceBanner> {
  late final TripWatcher _watcher = TripWatcher(dropPlace: widget.dropPlace);
  StreamSubscription<Coordinates>? _sub;
  Timer? _tick;
  TripSignals _signals = const TripSignals();

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final injected = widget.positions;
    if (injected == null && !await LocationService.ensurePermission()) return;
    if (!mounted) return;
    _sub = (injected ?? LocationService.positions()).listen((p) {
      _watcher.add(widget.now(), p.lat, p.lng);
      _refresh();
    }, onError: (_) {});
    // The halt rule depends on time passing without new samples.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
  }

  void _refresh() {
    if (mounted) setState(() => _signals = _watcher.signals(widget.now()));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  Widget _card(Key key, IconData icon, Color color, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AppCard(
          key: key,
          child: Row(children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = _signals;
    if (!s.any) return const SizedBox.shrink();
    return Column(children: [
      if (s.destinationReached) _card(const ValueKey('geoReached'), Icons.flag_circle_outlined, AppColors.success, tr(context, 'geoReached')),
      if (s.nearDestination)
        _card(const ValueKey('geoNear'), Icons.near_me_rounded, AppColors.primary, trf(context, 'geoNear', {'km': (s.kmToDrop ?? 0).round()})),
      if (s.longHalt) _card(const ValueKey('geoHalt'), Icons.pause_circle_outline_rounded, AppColors.warning, trf(context, 'geoHalt', {'m': TripWatcher.haltMinutes})),
    ]);
  }
}
