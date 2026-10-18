import 'package:flutter/material.dart';

import '../../core/dispatch/load_radar.dart';
import '../../core/features/features.dart';
import '../../core/matching/nearest.dart';
import '../../core/services/backend.dart';
import '../../core/services/features_service.dart';
import '../../core/services/load_service.dart';
import '../../core/services/user_service.dart';
import '../../core/services/vehicle_service.dart';
import '../../core/widgets/ds/feedback_kit.dart';
import 'incoming_load_screen.dart';

/// U28: owns the [LoadRadar] of the signed-in driver while [enabled] (the driver is online and `uiV2` is on) and opens
/// the Incoming Load Card whenever a load rings. The app has to be open: the push to a closed app comes with the
/// server wave, after the functions are deployed. [radar] shows the state to the home screen (the Radar line).
class IncomingLoadHost extends StatefulWidget {
  final bool enabled;
  final Widget child;
  final ValueChanged<String> onAccepted;
  final String? preferredVehicleId;
  final ValueChanged<LoadRadar?>? onRadar;

  /// Tests give their own radar.
  final LoadRadar Function()? radarFactory;

  const IncomingLoadHost({super.key, required this.enabled, required this.child, required this.onAccepted, this.preferredVehicleId, this.onRadar, this.radarFactory});

  @override
  State<IncomingLoadHost> createState() => _IncomingLoadHostState();
}

class _IncomingLoadHostState extends State<IncomingLoadHost> {
  LoadRadar? _radar;
  LatLng? _origin;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    QuietHours.load().then((q) => FeedbackKit.quiet = q);
    _sync();
  }

  @override
  void didUpdateWidget(IncomingLoadHost old) {
    super.didUpdateWidget(old);
    if (old.enabled != widget.enabled) _sync();
  }

  @override
  void dispose() {
    _radar?.dispose();
    super.dispose();
  }

  Future<void> _loadOrigin() async {
    try {
      _origin = UserService.lastLocationOf(await UserService.getUser());
    } catch (_) {}
  }

  void _sync() {
    if (widget.enabled && _radar == null) {
      _loadOrigin();
      final r = widget.radarFactory?.call() ??
          LoadRadar(
            loads: LoadService.watchOpen(),
            vehicles: VehicleService.fetchMyActive,
            origin: () => _origin,
            driverId: () => Backend.uid,
            wavesOn: () => FeaturesService.isOn(FeatureKey.dispatchV2),
          );
      _radar = r;
      r.states.listen(_onState);
      r.start();
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onRadar?.call(r));
    } else if (!widget.enabled && _radar != null) {
      _radar!.dispose();
      _radar = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onRadar?.call(null));
    }
  }

  void _onState(RadarState s) {
    if (!mounted || _open || s.current == null || _radar == null) return;
    _open = true;
    final radar = _radar!;
    Navigator.of(context).push<String>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => IncomingLoadScreen(radar: radar, onAccepted: widget.onAccepted, preferredVehicleId: widget.preferredVehicleId))).whenComplete(() {
      _open = false;
      // another card may have rung while this one was closing
      if (mounted && _radar == radar && radar.state.current != null) _onState(radar.state);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
