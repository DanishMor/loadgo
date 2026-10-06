import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/enterprise/business_roles.dart';
import '../core/l10n/l10n.dart';
import '../core/models/business.dart';
import '../core/services/business_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

String bizRoleLabel(BuildContext context, String role) => tr(context, switch (role) {
      BizRole.owner => 'roleOwner',
      BizRole.manager => 'roleManager',
      BizRole.dispatch => 'roleDispatch',
      BizRole.accounts => 'roleAccounts',
      BizRole.viewer => 'roleViewer',
      _ => 'teamRoleBooker',
    });

/// Company owner: invite team members by phone, see the team, remove a member.
class BusinessTeamScreen extends StatefulWidget {
  const BusinessTeamScreen({super.key});

  @override
  State<BusinessTeamScreen> createState() => _BusinessTeamScreenState();
}

class _BusinessTeamScreenState extends State<BusinessTeamScreen> {
  final _phone = TextEditingController();
  late final Stream<List<BusinessInvite>> _invites = BusinessService.watchInvitesSent().asBroadcastStream();
  late final Stream<List<BusinessMember>> _members = BusinessService.watchMembers().asBroadcastStream();
  bool _busy = false;
  String _role = BizRole.booker;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _invite() async {
    setState(() => _busy = true);
    try {
      await BusinessService.invite(_phone.text, role: _role);
      _phone.clear();
      if (mounted) showSnack(context, tr(context, 'fleetInviteSent'));
    } on BusinessTeamException catch (e) {
      if (mounted) {
        showSnack(context, tr(context, switch (e.reason) {
          'own_phone' => 'fleetInviteOwn',
          'already_member' => 'fleetInviteAlready',
          'no_company' => 'teamNeedCompany',
          _ => 'fleetInviteBadPhone',
        }));
      }
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'businessTeam'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr(context, 'teamInviteBooker'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            Row(children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('teamPhone'),
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  maxLength: 13,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                  decoration: InputDecoration(labelText: tr(context, 'mobile'), prefixText: '+91 ', counterText: ''),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(key: const ValueKey('teamInvite'), onPressed: _busy ? null : _invite, child: Text(tr(context, 'fleetInvite'))),
            ]),
            DropdownButtonFormField<String>(
              key: const ValueKey('teamRole'),
              initialValue: _role,
              decoration: InputDecoration(labelText: tr(context, 'teamRolePick')),
              items: [for (final r in BizRole.assignable) DropdownMenuItem(value: r, child: Text(bizRoleLabel(context, r)))],
              onChanged: (v) => setState(() => _role = v ?? _role),
            ),
            Text(tr(context, 'teamRoleNote'), style: TextStyle(color: AppColors.faint, fontSize: 12)),
          ]),
        ),
        const SizedBox(height: 14),
        Text(tr(context, 'businessTeam'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        LiveStream<List<BusinessMember>>(
          stream: () => _members,
          compact: true,
          builder: (context, members) => Column(children: [
            if (members.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(tr(context, 'teamNone'))),
            for (final m in members)
              ListTile(
                key: ValueKey('teamMember_${m.memberId}'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.badge_outlined),
                title: Text(m.memberName.isEmpty ? m.memberPhone : m.memberName),
                subtitle: Text(bizRoleLabel(context, m.role)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  PopupMenuButton<String>(
                    key: ValueKey('teamRoleMenu_${m.memberId}'),
                    tooltip: tr(context, 'teamRolePick'),
                    icon: const Icon(Icons.manage_accounts_outlined),
                    onSelected: (r) => BusinessService.setRole(m, r),
                    itemBuilder: (c) => [for (final r in BizRole.assignable) PopupMenuItem(value: r, child: Text(bizRoleLabel(c, r)))],
                  ),
                  TextButton(key: ValueKey('teamRemove_${m.memberId}'), onPressed: () => BusinessService.removeMember(m), child: Text(tr(context, 'remove'))),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 14),
        Text(tr(context, 'fleetInvitesSent'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        LiveStream<List<BusinessInvite>>(
          stream: () => _invites,
          compact: true,
          builder: (context, invites) => Column(children: [
            if (invites.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(tr(context, 'fleetNoInvites'))),
            for (final i in invites)
              ListTile(
                key: ValueKey('teamInvite_${i.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text(i.phone),
                subtitle: Text('${bizRoleLabel(context, i.role)} · ${tr(context, 'invite_${i.status}')}'),
                trailing: i.status == BusinessInvite.pending
                    ? TextButton(key: ValueKey('teamCancel_${i.id}'), onPressed: () => BusinessService.cancelInvite(i.id), child: Text(tr(context, 'cancel')))
                    : null,
              ),
          ]),
        ),
      ]),
    );
  }
}
