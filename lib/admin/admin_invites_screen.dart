import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/errors/friendly_error.dart';
import '../core/l10n/l10n.dart';
import '../core/pilot/invite_codes.dart';
import '../core/pilot/waitlist.dart';
import '../core/services/admin_console_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

/// Admin > Invite codes (MASTER-6 Task 1): make codes for a role and route,
/// see the uses left, switch one off, and let a phone number in without a code.
class AdminInvitesScreen extends StatefulWidget {
  /// Test hook; defaults to the live query.
  final Future<List<InviteCode>> Function()? load;
  const AdminInvitesScreen({super.key, this.load});

  @override
  State<AdminInvitesScreen> createState() => _AdminInvitesScreenState();
}

class _AdminInvitesScreenState extends State<AdminInvitesScreen> {
  late Future<List<InviteCode>> _data = (widget.load ?? InviteService.list)();
  final _route = TextEditingController();
  final _phone = TextEditingController();
  String _role = 'any';
  int _uses = 5;
  int _days = 30;
  bool _busy = false;
  bool _inviteOnly = false;
  final _cities = TextEditingController();

  void _refresh() {
    final next = (widget.load ?? InviteService.list)();
    setState(() {
      _data = next;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadPilot();
  }

  Future<void> _loadPilot() async {
    try {
      final c = await AdminConsoleService.readConfig('pilot');
      if (!mounted || c == null) return;
      setState(() {
        _inviteOnly = c['inviteOnly'] == true;
        _cities.text = PilotAreas.fromMap(c).openCities.join(', ');
      });
    } catch (_) {}
  }

  Future<void> _savePilot() async {
    final cities = [for (final c in _cities.text.split(',')) if (c.trim().isNotEmpty) c.trim()].take(PilotAreas.maxCities).toList();
    try {
      await AdminConsoleService.writeConfig('pilot', {'inviteOnly': _inviteOnly, 'openCities': cities});
      PilotAreas.invalidate();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'pilotSaved'))));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, FriendlyError.of(e)))));
    }
  }

  @override
  void dispose() {
    _cities.dispose();
    _route.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _make() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final code = await InviteService.create(role: _role, route: _route.text, maxUses: _uses, days: _days);
      await Clipboard.setData(ClipboardData(text: code));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$code  ${tr(context, 'copied')}')));
      _route.clear();
      _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, FriendlyError.of(e)))));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _allow() async {
    final digits = _phone.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 10) return;
    try {
      await InviteService.addWhitelist(digits.length == 10 ? '91$digits' : digits);
      _phone.clear();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'invAllowed'))));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, FriendlyError.of(e)))));
    }
  }

  String _roleLabel(String r) => r == 'any' ? tr(context, 'invRoleAny') : tr(context, r == 'fleet' ? 'fleetOwner' : r);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'adminInvites')), actions: [IconButton(tooltip: tr(context, 'retry'), onPressed: _refresh, icon: const Icon(Icons.refresh_rounded))]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SwitchListTile(key: const ValueKey('pilotInviteOnly'), contentPadding: EdgeInsets.zero, title: Text(tr(context, 'invPilotSwitch')), value: _inviteOnly, onChanged: (v) => setState(() => _inviteOnly = v)),
            TextField(key: const ValueKey('pilotCities'), controller: _cities, decoration: InputDecoration(labelText: tr(context, 'pilotCities'))),
            const SizedBox(height: 8),
            OutlinedButton(key: const ValueKey('pilotSave'), onPressed: _savePilot, child: Text(tr(context, 'save'))),
          ]),
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(context, 'invMake'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final r in InviteCode.roles) ChoiceChip(key: ValueKey('invRole_$r'), label: Text(_roleLabel(r)), selected: _role == r, onSelected: (_) => setState(() => _role = r)),
            ]),
            TextField(key: const ValueKey('invRoute'), controller: _route, maxLength: 60, decoration: InputDecoration(labelText: tr(context, 'invRoute'))),
            Row(children: [
              Expanded(child: DropdownButtonFormField<int>(key: const ValueKey('invUses'), initialValue: _uses, decoration: InputDecoration(labelText: tr(context, 'invUses')), items: [for (final n in const [1, 5, 10, 25, 50, 100]) DropdownMenuItem(value: n, child: Text('$n'))], onChanged: (v) => setState(() => _uses = v ?? 5))),
              const SizedBox(width: 12),
              Expanded(child: DropdownButtonFormField<int>(key: const ValueKey('invDays'), initialValue: _days, decoration: InputDecoration(labelText: tr(context, 'invDays')), items: [for (final n in const [7, 14, 30, 90]) DropdownMenuItem(value: n, child: Text('$n'))], onChanged: (v) => setState(() => _days = v ?? 30))),
            ]),
            const SizedBox(height: 8),
            FilledButton(key: const ValueKey('invMakeGo'), onPressed: _busy ? null : _make, child: Text(tr(context, 'invMake'))),
          ]),
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(context, 'invWhitelistHint'), style: const TextStyle(fontWeight: FontWeight.w700)),
            Row(children: [
              Expanded(child: TextField(key: const ValueKey('invPhone'), controller: _phone, keyboardType: TextInputType.phone, maxLength: 15)),
              const SizedBox(width: 8),
              OutlinedButton(key: const ValueKey('invAllow'), onPressed: _allow, child: Text(tr(context, 'invAllow'))),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<InviteCode>>(
          future: _data,
          builder: (context, snap) {
            if (snap.hasError) return ErrorState(error: snap.error, onRetry: _refresh);
            final list = snap.data;
            if (list == null) return const Center(child: CircularProgressIndicator());
            return Column(children: [
              for (final c in list)
                AppCard(
                  key: ValueKey('inv_${c.code}'),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: SelectableText(c.code, style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2)),
                    subtitle: Text('${_roleLabel(c.role)}${c.route.isEmpty ? '' : ' · ${c.route}'}\n${trf(context, 'invLeft', {'left': c.left, 'max': c.maxUses})}'),
                    isThreeLine: true,
                    trailing: TextButton(
                      key: ValueKey('invToggle_${c.code}'),
                      onPressed: () async {
                        await InviteService.setActive(c.code, !c.active);
                        _refresh();
                      },
                      child: Text(tr(context, c.active ? 'invSwitchOff' : 'invSwitchOn')),
                    ),
                  ),
                ),
            ]);
          },
        ),
      ]),
    );
  }
}
