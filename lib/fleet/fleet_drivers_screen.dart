import '../core/errors/error_text.dart';
import '../core/services/auth_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n/l10n.dart';
import '../core/models/fleet.dart';
import '../core/models/vehicle.dart';
import '../core/services/fleet_service.dart';
import '../core/services/vehicle_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

/// Invite drivers by phone number, see pending invites and members, remove a
/// member (their vehicles go back to the owner).
class FleetDriversScreen extends StatefulWidget {
  const FleetDriversScreen({super.key});

  @override
  State<FleetDriversScreen> createState() => _FleetDriversScreenState();
}

class _FleetDriversScreenState extends State<FleetDriversScreen> {
  final _phone = TextEditingController();
  late final Stream<List<FleetInvite>> _invites = FleetService.watchInvitesSent().asBroadcastStream();
  late final Stream<List<FleetMember>> _members = FleetService.watchMembers().asBroadcastStream();
  late final Stream<List<Vehicle>> _vehicles = VehicleService.watchMine().asBroadcastStream();
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _invite() async {
    setState(() => _busy = true);
    try {
      await FleetService.invite(_phone.text);
      _phone.clear();
      if (mounted) showSnack(context, tr(context, 'fleetInviteSent'));
    } on FleetException catch (e) {
      if (mounted) {
        showSnack(context, tr(context, switch (e.reason) {
          'own_phone' => 'fleetInviteOwn',
          'already_member' => 'fleetInviteAlready',
          _ => 'fleetInviteBadPhone',
        }));
      }
    } catch (error) {
      if (mounted) showSnack(context, errorText(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr(context, 'fleetInviteDriver'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          Row(children: [
            Expanded(
              child: TextField(
                key: const ValueKey('invitePhone'),
                controller: _phone,
                keyboardType: TextInputType.phone,
                maxLength: 13,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                decoration: InputDecoration(labelText: tr(context, 'mobile'), prefixText: '+91 ', counterText: ''),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(key: const ValueKey('inviteSend'), onPressed: _busy ? null : _invite, child: Text(tr(context, 'fleetInvite'))),
          ]),
          Text(tr(context, 'fleetInviteNote'), style: TextStyle(color: AppColors.faint, fontSize: 12)),
        ]),
      ),
      const SizedBox(height: 14),
      Text(tr(context, 'fleetMembers'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      LiveStream<List<FleetMember>>(
        stream: () => _members,
        compact: true,
        builder: (context, members) => LiveStream<List<Vehicle>>(
          stream: () => _vehicles,
          compact: true,
          builder: (context, vehicles) {
            final active = [for (final m in members) if (m.active) m];
            if (active.isEmpty) return Padding(padding: const EdgeInsets.all(12), child: Text(tr(context, 'fleetNoMembers')));
            return Column(children: [
              for (final m in active)
                ListTile(
                  key: ValueKey('member_${m.driverId}'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_rounded),
                  title: Text(m.driverName.isEmpty ? maskPhone(m.driverPhone) : m.driverName),
                  subtitle: Text(trf(context, 'fleetVehiclesAssigned', {'n': vehicles.where((v) => v.assignedDriverId == m.driverId).length})),
                  trailing: TextButton(
                    key: ValueKey('remove_${m.driverId}'),
                    onPressed: () => FleetService.removeMember(m, vehicleIds: [for (final v in vehicles) if (v.assignedDriverId == m.driverId) v.id]),
                    child: Text(tr(context, 'remove')),
                  ),
                ),
            ]);
          },
        ),
      ),
      const SizedBox(height: 14),
      Text(tr(context, 'fleetInvitesSent'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      LiveStream<List<FleetInvite>>(
        stream: () => _invites,
        compact: true,
        builder: (context, invites) => Column(children: [
          if (invites.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(tr(context, 'fleetNoInvites'))),
          for (final i in invites)
            ListTile(
              key: ValueKey('invite_${i.id}'),
              contentPadding: EdgeInsets.zero,
              title: Text(maskPhone(i.phone)),
              subtitle: Text(tr(context, 'invite_${i.status}')),
              trailing: i.status == FleetInvite.pending
                  ? TextButton(key: ValueKey('cancelInvite_${i.id}'), onPressed: () => FleetService.cancelInvite(i.id), child: Text(tr(context, 'cancel')))
                  : null,
            ),
        ]),
      ),
    ]);
  }
}
