import '../core/bilty/lr_register_screen.dart';
import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/fleet.dart';
import '../core/models/vehicle.dart';
import '../core/services/auth_helpers.dart';
import '../core/services/backend.dart';
import '../core/services/fleet_service.dart';
import '../core/services/transporter_service.dart';
import '../core/services/vehicle_service.dart';
import '../core/transporter/transporter_logic.dart';
import '../core/widgets/common.dart';
import '../core/widgets/logistics_labels.dart';
import 'fleet_analytics_screen.dart';
import 'transporter_books_screen.dart';
import 'transporter_profile_screen.dart';

/// Top of the transporter dashboard: the "finish your company profile" card,
/// the papers that expire soon across the whole fleet (own and attached
/// vehicles), and shortcuts to the company profile, the books and analytics.
class TransporterShortcuts extends StatefulWidget {
  /// Injectable for tests.
  final Future<TransporterProfile> Function()? profile;
  final Stream<List<Vehicle>>? vehicles;
  final Stream<List<FleetMember>>? members;
  final DateTime Function() now;

  const TransporterShortcuts({super.key, this.profile, this.vehicles, this.members, this.now = DateTime.now});

  @override
  State<TransporterShortcuts> createState() => _TransporterShortcutsState();
}

class _TransporterShortcutsState extends State<TransporterShortcuts> {
  late Future<TransporterProfile> _profile = _loadProfile();
  late final Stream<List<Vehicle>> _vehicles = (widget.vehicles ?? _fleetVehicles()).asBroadcastStream();
  late final Stream<List<FleetMember>> _members = (widget.members ?? FleetService.watchMembers()).asBroadcastStream();

  Future<TransporterProfile> _loadProfile() async {
    try {
      return await (widget.profile ?? TransporterService.loadProfile)();
    } catch (_) {
      // Offline: no card rather than an error.
      return const TransporterProfile(officeCity: '-');
    }
  }

  Stream<List<Vehicle>> _fleetVehicles() async* {
    if (Backend.uid == null) {
      yield const [];
      return;
    }
    await for (final own in VehicleService.watchMine()) {
      var attached = const <Vehicle>[];
      try {
        attached = await TransporterService.watchAttached().first.timeout(const Duration(seconds: 8));
      } catch (_) {
        // Offline or slow: the reminders for the own vehicles still show.
      }
      yield {for (final v in [...own, ...attached]) v.id: v}.values.toList();
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) {
      setState(() {
        _profile = _loadProfile();
      });
    }
  }

  String _when(BuildContext context, DocReminder r) {
    if (r.expired) return tr(context, 'trpExpired');
    if (r.daysLeft == 0) return tr(context, 'trpExpiresToday');
    return trf(context, 'trpExpiresIn', {'n': r.daysLeft});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FutureBuilder<TransporterProfile>(
          future: _profile,
          builder: (context, snap) {
            final p = snap.data;
            if (p == null || !p.needsCompletion) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                key: const ValueKey('trpCompleteCard'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.business_outlined, color: AppColors.warning),
                    const SizedBox(width: 10),
                    Expanded(child: Text(tr(context, 'trpCompleteCard'))),
                  ]),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton(onPressed: () => _open(const TransporterProfileScreen()), child: Text(tr(context, 'trpTitle'))),
                  ),
                ]),
              ),
            );
          },
        ),
        StreamBuilder<List<FleetMember>>(
          stream: _members,
          builder: (context, memSnap) => StreamBuilder<List<Vehicle>>(
          stream: _vehicles,
          builder: (context, snap) {
            final reminders = docReminders(snap.data ?? const [], widget.now());
            final licences = licenceReminders(memSnap.data ?? const [], widget.now());
            if (reminders.isEmpty && licences.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                key: const ValueKey('trpDocReminders'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.event_busy_outlined, color: (reminders.isNotEmpty && reminders.first.expired) || (licences.isNotEmpty && licences.first.expired) ? Colors.red : AppColors.warning),
                    const SizedBox(width: 8),
                    Expanded(child: Text(tr(context, 'trpDocsTitle'), style: const TextStyle(fontWeight: FontWeight.w800))),
                  ]),
                  for (final r in reminders.take(5))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        trf(context, 'trpDocLine', {'vehicle': r.vehicle.number, 'doc': vehicleDocLabel(context, r.kind), 'when': _when(context, r)}),
                        key: ValueKey('docReminder_${r.vehicle.id}_${r.kind}'),
                      ),
                    ),
                  for (final l in licences.take(5))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        trf(context, 'trpDocLine', {
                          'vehicle': l.member.driverName.isEmpty ? maskPhone(l.member.driverPhone) : l.member.driverName,
                          'doc': tr(context, 'docNameDl'),
                          'when': l.expired ? tr(context, 'trpExpired') : (l.daysLeft == 0 ? tr(context, 'trpExpiresToday') : trf(context, 'trpExpiresIn', {'n': l.daysLeft})),
                        }),
                        key: ValueKey('licenceReminder_${l.member.driverId}'),
                      ),
                    ),
                ]),
              ),
            );
          },
        ),
        ),
        Wrap(spacing: 8, children: [
          ActionChip(
            key: const ValueKey('trpOpenProfile'),
            avatar: const Icon(Icons.business_outlined, size: 18),
            label: Text(tr(context, 'trpTitle')),
            onPressed: () => _open(const TransporterProfileScreen()),
          ),
          ActionChip(
            key: const ValueKey('trpOpenBooks'),
            avatar: const Icon(Icons.account_balance_wallet_outlined, size: 18),
            label: Text(tr(context, 'trpBooks')),
            onPressed: () => _open(const TransporterBooksScreen()),
          ),
          ActionChip(
            key: const ValueKey('trpOpenLrs'),
            avatar: const Icon(Icons.description_outlined, size: 18),
            label: Text(tr(context, 'lrrTitle')),
            onPressed: () => _open(const LrRegisterScreen()),
          ),
          ActionChip(
            key: const ValueKey('trpOpenAnalytics'),
            avatar: const Icon(Icons.insights_outlined, size: 18),
            label: Text(tr(context, 'fleetAnalytics')),
            onPressed: () => _open(Scaffold(
              backgroundColor: AppColors.background,
              appBar: AppBar(backgroundColor: AppColors.background, scrolledUnderElevation: 0, title: Text(tr(context, 'fleetAnalytics'))),
              body: const FleetAnalyticsScreen(),
            )),
          ),
        ]),
      ]),
    );
  }
}
