import '../core/widgets/admin_phone.dart';
import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/risk.dart';
import '../core/identity/profile_extras.dart';
import '../core/services/admin_user_service.dart';
import '../core/widgets/kyc_check_widgets.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';
import 'flagged_users_screen.dart' show riskTierLabel;
import 'user_risk_checks.dart';

/// Admin > Users > one user: status, suspend / ban / restore, force
/// re-verification, internal notes and the history of admin actions.
class AdminUserScreen extends StatefulWidget {
  final String uid;

  const AdminUserScreen({super.key, required this.uid});

  @override
  State<AdminUserScreen> createState() => _AdminUserScreenState();
}

class _AdminUserScreenState extends State<AdminUserScreen> {
  final _note = TextEditingController();
  late final Stream<Map<String, dynamic>?> _user = AdminUserService.watchUser(widget.uid).asBroadcastStream();
  late final Stream<List<AdminNote>> _notes = AdminUserService.watchNotes(widget.uid).asBroadcastStream();
  late final Stream<List<UserActionEvent>> _history = AdminUserService.watchHistory(widget.uid).asBroadcastStream();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<String?> _askReason(String title) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(key: const ValueKey('actionReason'), controller: ctrl, maxLength: 200, autofocus: true, decoration: InputDecoration(labelText: tr(c, 'auReason'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr(c, 'cancel'))),
          FilledButton(key: const ValueKey('actionConfirm'), onPressed: () => Navigator.pop(c, ctrl.text), child: Text(tr(c, 'save'))),
        ],
      ),
    );
    return reason;
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) showSnack(context, tr(context, 'auDone'));
    } on UserActionException catch (e) {
      if (mounted) showSnack(context, tr(context, e.reason == 'reason' ? 'auReasonNeeded' : 'somethingWrong'));
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  Future<void> _standing(String action, String titleKey) async {
    String? reason = '';
    if (action != UserAction.unban) {
      reason = await _askReason(tr(context, titleKey));
      if (reason == null) return;
    }
    await _run(() => AdminUserService.setStanding(widget.uid, action, reason: reason!));
  }

  Future<void> _reverify() async {
    final reason = await _askReason(tr(context, 'auReverify'));
    if (reason == null) return;
    await _run(() => AdminUserService.forceReverify(widget.uid, reason: reason));
  }

  Future<void> _flag() async {
    var kind = ReviewKind.name;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setSt) => AlertDialog(
          title: Text(tr(c, 'flagMismatch')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              key: const ValueKey('flagKind'),
              isExpanded: true,
              initialValue: kind,
              items: [for (final k in ReviewKind.all) DropdownMenuItem(value: k, child: Text(reviewKindLabel(c, k)))],
              onChanged: (v) => setSt(() => kind = v ?? kind),
            ),
            TextField(key: const ValueKey('flagNote'), controller: ctrl, maxLength: 200, decoration: InputDecoration(labelText: tr(c, 'auReason'))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr(c, 'cancel'))),
            FilledButton(key: const ValueKey('flagConfirm'), onPressed: () => Navigator.pop(c, true), child: Text(tr(c, 'save'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _run(() => AdminUserService.setReviewFlag(widget.uid, kind, ctrl.text));
  }

  Future<void> _addNote() async {
    final text = _note.text;
    if (text.trim().isEmpty) return;
    _note.clear();
    await _run(() => AdminUserService.addNote(widget.uid, text));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'adminUsers'))),
      body: LiveStream<Map<String, dynamic>?>(
        stream: () => _user,
        builder: (context, user) {
          final u = user ?? const <String, dynamic>{};
          final tier = u['riskTier'] as String? ?? RiskTier.normal;
          final name = (u['name'] ?? u['driverName'] ?? widget.uid).toString();
          final isDriver = u['driverName'] != null || ((u['roles'] as List?)?.contains('driver') ?? false);
          final standingOk = tier == RiskTier.normal || tier == RiskTier.review;
          return ListView(padding: const EdgeInsets.all(20), children: [
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                Row(children: [
                  AdminPhoneText(uid: widget.uid, phone: '${u['phone'] ?? ''}', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  Text('  ·  ${widget.uid}', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                ]),
                const SizedBox(height: 8),
                Text('${tr(context, 'auStatus')}: ${riskTierLabel(context, tier)}', key: const ValueKey('userStanding'), style: const TextStyle(fontWeight: FontWeight.w700)),
                if ((u['riskReason'] as String?)?.isNotEmpty ?? false) Text(u['riskReason'] as String, style: TextStyle(color: AppColors.muted)),
                if (isDriver) Text('${tr(context, 'driverVerification')}: ${u['verificationStatus'] ?? 'pending'}', style: TextStyle(color: AppColors.muted)),
                if (isDriver) ...[const SizedBox(height: 8), Text(tr(context, 'autoCheckTitle'), style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 4), AutoCheckChips(user: u)],
                if (ProfileExtras.fromProfile(u).currentAddress.isNotEmpty) Text('${tr(context, 'addrCurrent')}: ${maskAddress(ProfileExtras.fromProfile(u).currentAddress)}', key: const ValueKey('maskedAddr'), style: TextStyle(color: AppColors.muted)),
                if (ProfileExtras.fromProfile(u).upiId.isNotEmpty) Text('UPI: ${maskUpiId(ProfileExtras.fromProfile(u).upiId)}', key: const ValueKey('maskedUpi'), style: TextStyle(color: AppColors.muted)),
              ]),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (standingOk || tier == RiskTier.restricted)
                OutlinedButton(key: const ValueKey('actSuspend'), onPressed: () => _standing(UserAction.suspend, 'auSuspend'), child: Text(tr(context, 'auSuspend'))),
              if (tier != RiskTier.banned)
                OutlinedButton(key: const ValueKey('actBan'), onPressed: () => _standing(UserAction.ban, 'auBan'), child: Text(tr(context, 'auBan'))),
              if (tier == RiskTier.suspended || tier == RiskTier.banned || tier == RiskTier.restricted)
                FilledButton(key: const ValueKey('actUnban'), onPressed: () => _standing(UserAction.unban, 'auUnban'), child: Text(tr(context, 'auUnban'))),
              if (isDriver) OutlinedButton(key: const ValueKey('actReverify'), onPressed: _reverify, child: Text(tr(context, 'auReverify'))),
              if (isDriver && u['reviewFlag'] is! Map) OutlinedButton(key: const ValueKey('actFlag'), onPressed: _flag, child: Text(tr(context, 'flagMismatch'))),
              if (u['reviewFlag'] is Map) OutlinedButton(key: const ValueKey('actUnflag'), onPressed: () => _run(() => AdminUserService.clearReviewFlag(widget.uid)), child: Text(tr(context, 'clearFlag'))),
            ]),
            const SizedBox(height: 20),
            UserRiskChecks(uid: widget.uid, isDriver: isDriver),
            const SizedBox(height: 20),
            Text(tr(context, 'auNotes'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Row(children: [
              Expanded(child: TextField(key: const ValueKey('noteField'), controller: _note, maxLength: 1000, decoration: InputDecoration(hintText: tr(context, 'auNoteHint'), counterText: ''))),
              IconButton(tooltip: tr(context, 'a11yAddNote'), key: const ValueKey('noteAdd'), icon: const Icon(Icons.add_comment_outlined), onPressed: _addNote),
            ]),
            LiveStream<List<AdminNote>>(
              stream: () => _notes,
              compact: true,
              builder: (context, notes) => notes.isEmpty
                  ? Text(tr(context, 'auNoNotes'), style: TextStyle(color: AppColors.muted))
                  : Column(children: [
                      for (final n in notes)
                        ListTile(contentPadding: EdgeInsets.zero, dense: true, title: Text(n.text), subtitle: Text(n.createdAt == null ? n.by : '${n.by} · ${formatDateTime(n.createdAt!)}')),
                    ]),
            ),
            const SizedBox(height: 20),
            Text(tr(context, 'auHistory'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            LiveStream<List<UserActionEvent>>(
              stream: () => _history,
              compact: true,
              builder: (context, events) => events.isEmpty
                  ? Text(tr(context, 'auNoHistory'), style: TextStyle(color: AppColors.muted))
                  : Column(children: [
                      for (final e in events)
                        ListTile(
                          key: ValueKey('hist_${e.action}'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(tr(context, 'auAction_${e.action}')),
                          subtitle: Text([if (e.reason.isNotEmpty) e.reason, e.actorId, if (e.at != null) formatDateTime(e.at!)].join(' · ')),
                        ),
                    ]),
            ),
          ]);
        },
      ),
    );
  }
}
