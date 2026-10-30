import 'package:flutter/material.dart';

import '../../core/dispatch/load_radar.dart';
import '../../core/l10n/l10n.dart';
import '../../core/models/booking.dart';
import '../../core/models/vehicle.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/ds/app_button.dart';
import '../../core/widgets/live_stream.dart';
import '../earnings_view.dart' show TodayEarningsText;

/// What the Radar line under the online switch says (U27). Pure, so a test can read every case.
enum RadarLine { offline, noTruck, searching, waiting }

RadarLine radarLine({required bool online, required int vehicleCount, required int waiting}) {
  if (!online) return RadarLine.offline;
  if (vehicleCount == 0) return RadarLine.noTruck;
  return waiting > 0 ? RadarLine.waiting : RadarLine.searching;
}

/// The vehicle the driver chose for today, or the first one when nothing (or a sold one) is chosen.
Vehicle? pickVehicle(List<Vehicle> all, String? chosenId) {
  if (all.isEmpty) return null;
  for (final v in all) {
    if (v.id == chosenId) return v;
  }
  return all.first;
}

/// U27: the driver's new home. A big online switch with today's earnings, the Radar line (is the app looking for
/// loads), the truck chosen for today, the trip in progress and the ones coming up. Papers and other alerts come in
/// [banners]; the older tools sit under "More" in [more]. The host (the driver home screen) owns the data.
class DriverHomeV2 extends StatelessWidget {
  final bool online;
  final ValueChanged<bool> onOnline;
  final Stream<List<Vehicle>> vehicles;
  final Stream<List<Booking>> todayTrips;
  final String? vehicleId;
  final ValueChanged<String> onVehicle;
  final Stream<RadarState>? radar;
  final VoidCallback onAddVehicle;
  final VoidCallback onOpenLoads;
  final Widget header;
  final List<Widget> banners;
  final List<Widget> trips;
  final List<Widget> more;

  const DriverHomeV2({
    super.key,
    required this.online,
    required this.onOnline,
    required this.vehicles,
    required this.todayTrips,
    required this.vehicleId,
    required this.onVehicle,
    required this.onAddVehicle,
    required this.onOpenLoads,
    required this.header,
    this.radar,
    this.banners = const [],
    this.trips = const [],
    this.more = const [],
  });

  String _radarText(BuildContext context, RadarLine l, int waiting) => switch (l) {
        RadarLine.offline => tr(context, 'dhRadarOff'),
        RadarLine.noTruck => tr(context, 'dhRadarNoTruck'),
        RadarLine.searching => tr(context, 'dhRadarOn'),
        RadarLine.waiting => trf(context, 'dhRadarWait', {'n': waiting}),
      };

  Widget _radarRow(BuildContext context, List<Vehicle> vs) {
    final on = online ? DsHero.on : context.ds.onPrimary;
    return StreamBuilder<RadarState>(
      stream: radar,
      builder: (context, snap) {
        final waiting = snap.data == null ? 0 : (snap.data!.current == null ? 0 : 1 + snap.data!.waiting);
        final line = radarLine(online: online, vehicleCount: vs.length, waiting: waiting);
        final active = line == RadarLine.searching || line == RadarLine.waiting;
        return Semantics(
          container: true,
          liveRegion: true,
          child: Row(key: const ValueKey('dhRadar'), children: [
            Icon(active ? Icons.radar_rounded : Icons.wifi_off_rounded, size: 22, color: active ? on : on.withValues(alpha: 0.7)),
            const SizedBox(width: DsSpace.s2),
            Expanded(child: Text(_radarText(context, line, waiting), style: DsType.bodySmall.copyWith(color: on))),
          ]),
        );
      },
    );
  }

  Widget _hero(BuildContext context, List<Vehicle> vs) {
    final c = context.ds;
    // White on the navy gradient while online; the theme's onPrimary on the grey card while offline.
    final on = online ? DsHero.on : c.onPrimary;
    return Container(
      key: const ValueKey('dhHero'),
      padding: const EdgeInsets.all(DsSpace.s5),
      decoration: BoxDecoration(
        gradient: online ? const LinearGradient(colors: DsHero.colors, begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
        color: online ? null : c.textMuted,
        borderRadius: DsRadius.all(DsRadius.xl),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(tr(context, online ? 'dhOnlineOn' : 'dhOnlineOff'), style: DsType.headline.copyWith(color: on))),
          // a big target for a thumb: the switch is scaled up
          Transform.scale(scale: 1.35, child: Switch(key: const ValueKey('onlineSwitch'), value: online, onChanged: onOnline)),
        ]),
        const SizedBox(height: DsSpace.s3),
        _radarRow(context, vs),
        const SizedBox(height: DsSpace.s4),
        Text(tr(context, 'todayEarnings'), style: DsType.bodySmall.copyWith(color: on.withValues(alpha: 0.85))),
        const SizedBox(height: DsSpace.s1),
        TodayEarningsText(bookings: todayTrips),
      ]),
    );
  }

  Widget _vehicleSelector(BuildContext context, List<Vehicle> vs) {
    final c = context.ds;
    if (vs.isEmpty) {
      return AppCard(
        key: const ValueKey('dhNoTruck'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.local_shipping_rounded, color: c.warning),
            const SizedBox(width: DsSpace.s3),
            Expanded(child: Text(tr(context, 'noVehicleTitle'), style: DsType.subtitle.copyWith(color: c.textStrong))),
          ]),
          const SizedBox(height: DsSpace.s3),
          AppButton(key: const ValueKey('dhAddTruck'), label: tr(context, 'addVehicle'), kind: AppButtonKind.secondary, onPressed: onAddVehicle),
        ]),
      );
    }
    final chosen = pickVehicle(vs, vehicleId)!;
    return Column(key: const ValueKey('dhVehicles'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr(context, 'dhTruckToday'), style: DsType.label.copyWith(color: c.textMuted)),
      const SizedBox(height: DsSpace.s2),
      Wrap(spacing: DsSpace.s2, runSpacing: DsSpace.s2, children: [
        for (final v in vs)
          ChoiceChip(
            key: ValueKey('dhVehicle_${v.id}'),
            avatar: const Icon(Icons.local_shipping_outlined, size: 18),
            label: Text('${v.number} · ${v.type}'),
            selected: v.id == chosen.id,
            onSelected: (_) => onVehicle(v.id),
          ),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return SafeArea(
      child: LiveStream<List<Vehicle>>(
        stream: () => vehicles,
        compact: true,
        builder: (context, vs) => ListView(padding: const EdgeInsets.all(DsSpace.gutter), children: [
          header,
          const SizedBox(height: DsSpace.s4),
          _hero(context, vs),
          const SizedBox(height: DsSpace.s4),
          _vehicleSelector(context, vs),
          const SizedBox(height: DsSpace.s4),
          ...banners,
          ...trips,
          if (online)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(key: const ValueKey('dhBrowse'), onPressed: onOpenLoads, icon: const Icon(Icons.inventory_2_outlined), label: Text(tr(context, 'availableLoads'))),
            ),
          if (more.isNotEmpty) ...[
            const SizedBox(height: DsSpace.s4),
            Semantics(header: true, child: Text(tr(context, 'dhMore'), style: DsType.title.copyWith(color: c.textStrong))),
            const SizedBox(height: DsSpace.s2),
            ...more,
          ],
        ]),
      ),
    );
  }
}
