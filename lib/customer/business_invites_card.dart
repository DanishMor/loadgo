import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/business.dart';
import '../core/services/business_service.dart';
import '../core/widgets/common.dart';

/// Customer home: invites to join a company as a booker, and the companies
/// the customer already books for. Empty = nothing shown.
class BusinessInvitesCard extends StatefulWidget {
  final Stream<List<BusinessInvite>>? invites;
  final Stream<List<BusinessMember>>? memberships;

  const BusinessInvitesCard({super.key, this.invites, this.memberships});

  @override
  State<BusinessInvitesCard> createState() => _BusinessInvitesCardState();
}

class _BusinessInvitesCardState extends State<BusinessInvitesCard> {
  late final Stream<List<BusinessInvite>> _invites = (widget.invites ?? BusinessService.watchMyInvites()).asBroadcastStream();
  late final Stream<List<BusinessMember>> _mine = (widget.memberships ?? BusinessService.watchMyMemberships()).asBroadcastStream();

  Future<void> _answer(BusinessInvite i, bool accept) async {
    try {
      await BusinessService.respond(i, accept: accept);
      if (mounted && accept) showSnack(context, tr(context, 'teamJoined'));
    } on BusinessTeamException {
      if (mounted) showSnack(context, tr(context, 'teamNeedCustomer'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BusinessInvite>>(
      stream: _invites,
      builder: (context, inv) => StreamBuilder<List<BusinessMember>>(
        stream: _mine,
        builder: (context, mem) {
          final invites = inv.data ?? const <BusinessInvite>[];
          final mine = mem.data ?? const <BusinessMember>[];
          if (invites.isEmpty && mine.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final i in invites) ...[
                  Text(trf(context, 'teamInviteFrom', {'name': i.ownerName.isEmpty ? i.phone : i.ownerName}), key: ValueKey('bizInviteText_${i.id}')),
                  Row(children: [
                    TextButton(key: ValueKey('bizDecline_${i.id}'), onPressed: () => _answer(i, false), child: Text(tr(context, 'decline'))),
                    FilledButton(key: ValueKey('bizJoin_${i.id}'), onPressed: () => _answer(i, true), child: Text(tr(context, 'fleetJoin'))),
                  ]),
                ],
                for (final m in mine)
                  Row(children: [
                    Expanded(child: Text(trf(context, 'teamBookingFor', {'name': m.ownerName.isEmpty ? m.ownerId : m.ownerName}), key: ValueKey('bizMember_${m.id}'))),
                    TextButton(key: ValueKey('bizLeave_${m.id}'), onPressed: () => BusinessService.leave(m), child: Text(tr(context, 'fleetLeave'))),
                  ]),
              ]),
            ),
          );
        },
      ),
    );
  }
}
