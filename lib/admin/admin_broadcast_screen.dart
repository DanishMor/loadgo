import 'package:flutter/material.dart';

import '../core/errors/error_text.dart';
import '../core/l10n/l10n.dart';
import '../core/services/server_actions.dart';
import '../core/theme/design_tokens.dart';
import '../core/widgets/common.dart';
import '../core/widgets/ds/app_button.dart';

/// Admin: an announcement push to a role or to everyone (F27, switch
/// `adminBroadcast`, staff roles super, support and ops). The server checks the
/// role, honours each person's notification switches and quiet hours, and
/// writes the audit line. The text goes out as it is typed, so keep it short;
/// it is not translated automatically.
class AdminBroadcastScreen extends StatefulWidget {
  /// Replaced in tests.
  final Future<int?> Function({required String title, required String body, String? role}) send;

  const AdminBroadcastScreen({super.key, this.send = ServerActions.broadcast});

  @override
  State<AdminBroadcastScreen> createState() => _AdminBroadcastScreenState();
}

class _AdminBroadcastScreenState extends State<AdminBroadcastScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String? _role; // null = everyone
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _title.text.trim(), b = _body.text.trim();
    if (t.length < 3 || b.length < 3) {
      showSnack(context, tr(context, 'bcTooShort'));
      return;
    }
    // A mass push cannot be taken back: ask once, naming the audience.
    final who = tr(context, const {null: 'bcAll', 'driver': 'bcDrivers', 'customer': 'bcCustomers', 'fleet': 'bcFleet'}[_role]!);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr(c, 'bcConfirmTitle')),
        content: Text(trf(c, 'bcConfirmBody', {'who': who})),
        actions: [
          TextButton(key: const ValueKey('bcCancel'), onPressed: () => Navigator.pop(c, false), child: Text(tr(c, 'cancel'))),
          FilledButton(key: const ValueKey('bcConfirm'), onPressed: () => Navigator.pop(c, true), child: Text(tr(c, 'bcSend'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final n = await widget.send(title: t, body: b, role: _role);
      if (!mounted) return;
      if (n == null) {
        showSnack(context, tr(context, 'bcNoServer'));
      } else {
        showSnack(context, trf(context, 'bcSent', {'n': n}));
        _title.clear();
        _body.clear();
      }
    } on ServerRefused catch (e) {
      if (mounted) showSnack(context, e.code == 'permission-denied' ? tr(context, 'errorNoAccess') : errorText(context, e));
    } catch (error) {
      if (mounted) showSnack(context, errorText(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'adminBroadcast'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(DsSpace.gutter),
          children: [
            TextField(
              key: const ValueKey('bcTitle'),
              controller: _title,
              maxLength: 80,
              decoration: InputDecoration(labelText: tr(context, 'bcTitleLabel')),
            ),
            const SizedBox(height: DsSpace.s3),
            TextField(
              key: const ValueKey('bcBody'),
              controller: _body,
              maxLength: 160,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(labelText: tr(context, 'bcBodyLabel')),
            ),
            const SizedBox(height: DsSpace.s3),
            Text(tr(context, 'bcAudience'), style: DsType.caption.copyWith(color: context.ds.textMuted)),
            const SizedBox(height: DsSpace.s1),
            Wrap(spacing: DsSpace.s2, runSpacing: DsSpace.s2, children: [
              for (final (value, key) in const [(null, 'bcAll'), ('driver', 'bcDrivers'), ('customer', 'bcCustomers'), ('fleet', 'bcFleet')])
                ChoiceChip(
                  key: ValueKey('bcRole_${value ?? 'all'}'),
                  label: Text(tr(context, key)),
                  selected: _role == value,
                  onSelected: (_) => setState(() => _role = value),
                ),
            ]),
            const SizedBox(height: DsSpace.s6),
            AppButton(key: const ValueKey('bcSend'), label: tr(context, 'bcSend'), icon: Icons.campaign_outlined, loading: _busy, onPressed: _send),
          ],
        ),
      ),
    );
  }
}
