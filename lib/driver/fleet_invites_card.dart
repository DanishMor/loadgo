import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/fleet.dart';
import '../core/services/fleet_service.dart';
import '../core/widgets/common.dart';

/// Driver home: pending invites from fleet owners (matched by phone number)
/// and the fleets the driver already belongs to. Shows nothing when empty.
class FleetInvitesCard extends StatefulWidget {
  final Stream<List<FleetInvite>>? invites;
  final Stream<List<FleetMember>>? fleets;

  const FleetInvitesCard({super.key, this.invites, this.fleets});

  @override
  State<FleetInvitesCard> createState() => _FleetInvitesCardState();
}

class _FleetInvitesCardState extends State<FleetInvitesCard> {
  late final Stream<List<FleetInvite>> _invites = (widget.invites ?? FleetService.watchMyInvites()).asBroadcastStream();
  late final Stream<List<FleetMember>> _fleets = (widget.fleets ?? FleetService.watchMyFleets()).asBroadcastStream();

  Future<void> _answer(FleetInvite i, bool accept) async {
    try {
      await FleetService.respond(i, accept: accept);
      if (mounted && accept) showSnack(context, tr(context, 'fleetJoined'));
    } on FleetException {
      if (mounted) showSnack(context, tr(context, 'fleetNeedDriverRole'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FleetInvite>>(
      stream: _invites,
      builder: (context, inv) => StreamBuilder<List<FleetMember>>(
        stream: _fleets,
        builder: (context, fl) {
          final invites = inv.data ?? const <FleetInvite>[];
          final fleets = fl.data ?? const <FleetMember>[];
          if (invites.isEmpty && fleets.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final i in invites) ...[
                  Text(trf(context, 'fleetInviteFrom', {'name': i.ownerName.isEmpty ? i.phone : i.ownerName}), key: ValueKey('inviteText_${i.id}')),
                  Row(children: [
                    TextButton(key: ValueKey('decline_${i.id}'), onPressed: () => _answer(i, false), child: Text(tr(context, 'decline'))),
                    FilledButton(key: ValueKey('join_${i.id}'), onPressed: () => _answer(i, true), child: Text(tr(context, 'fleetJoin'))),
                  ]),
                ],
                for (final m in fleets)
                  Row(children: [
                    Expanded(child: Text(trf(context, 'fleetOwnerLabel', {'name': m.ownerName.isEmpty ? m.ownerId : m.ownerName}), key: ValueKey('fleet_${m.id}'))),
                    TextButton(key: ValueKey('leave_${m.id}'), onPressed: () => FleetService.leave(m), child: Text(tr(context, 'fleetLeave'))),
                  ]),
              ]),
            ),
          );
        },
      ),
    );
  }
}
