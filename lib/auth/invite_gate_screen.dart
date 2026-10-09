import 'package:flutter/material.dart';

import '../core/app_info.dart';
import '../core/l10n/l10n.dart';
import '../core/pilot/invite_codes.dart';
import '../core/services/backend.dart';

/// Shown to a new person while the pilot needs an invite (MASTER-6 Task 1).
/// [role] is customer, driver or fleet; [next] builds the profile screen.
class InviteGateScreen extends StatefulWidget {
  final String role;
  final Widget Function() next;
  const InviteGateScreen({super.key, required this.role, required this.next});

  @override
  State<InviteGateScreen> createState() => _InviteGateScreenState();
}

class _InviteGateScreenState extends State<InviteGateScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  static const _messages = {
    InviteCheck.unknown: 'inviteUnknown',
    InviteCheck.wrongRole: 'inviteWrongRole',
    InviteCheck.expired: 'inviteExpired',
    InviteCheck.usedUp: 'inviteUsedUp',
    InviteCheck.off: 'inviteOff',
  };

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await InviteService.redeem(_code.text, role: widget.role);
      if (!mounted) return;
      if (res == InviteCheck.ok) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => widget.next()));
        return;
      }
      setState(() => _error = _messages[res]);
    } catch (_) {
      if (mounted) setState(() => _error = 'inviteUnknown');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'inviteTitle'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(trf(context, 'inviteBody', {'app': AppInfo.name}), key: const ValueKey('inviteBody')),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('inviteCode'),
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          maxLength: 12,
          decoration: InputDecoration(labelText: tr(context, 'inviteHint'), errorText: _error == null ? null : tr(context, _error!)),
          onSubmitted: (_) => _go(),
        ),
        const SizedBox(height: 8),
        FilledButton(key: const ValueKey('inviteGo'), onPressed: _busy ? null : _go, child: Text(tr(context, 'inviteContinue'))),
      ]),
    );
  }
}

/// Wraps a profile screen: returns the invite screen when the pilot needs a
/// code and this person has neither a code nor a place on the list.
Future<Widget> withInviteGate(String role, Widget Function() next) async {
  final user = Backend.currentUser;
  if (user == null) return next();
  final ok = await InviteService.mayJoin(uid: user.uid, phone: user.phoneNumber);
  return ok ? next() : InviteGateScreen(role: role, next: next);
}
