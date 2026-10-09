import '../core/errors/error_text.dart';
import '../core/services/auth_helpers.dart';
import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/risk.dart';
import '../core/risk/risk_rules.dart';
import '../core/services/risk_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

/// Users an admin should look at: non-normal tier, many cancellations or
/// open reports. Tap one to change the risk tier. Rules gate every write.
class FlaggedUsersScreen extends StatefulWidget {
  const FlaggedUsersScreen({super.key});

  @override
  State<FlaggedUsersScreen> createState() => _FlaggedUsersScreenState();
}

String riskTierLabel(BuildContext context, String tier) => tr(context, switch (tier) {
      RiskTier.review => 'riskReview',
      RiskTier.restricted => 'riskRestricted',
      RiskTier.suspended => 'riskSuspended',
      RiskTier.banned => 'riskBanned',
      _ => 'riskNormal',
    });

/// Dialog to pick a new risk tier and reason; saves it (rules: admins only).
/// Returns true when the tier was saved.
Future<bool> editRiskTier(BuildContext context, {required String uid, required String name, required String tier}) async {
  final reason = TextEditingController();
  var picked = tier;
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(name),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          RadioGroup<String>(
            groupValue: picked,
            onChanged: (v) => setLocal(() => picked = v!),
            child: Column(children: [
              for (final t in RiskTier.all)
                RadioListTile<String>(key: ValueKey('tier_$t'), value: t, title: Text(riskTierLabel(ctx, t))),
            ]),
          ),
          TextField(
            controller: reason,
            maxLength: 200,
            decoration: InputDecoration(labelText: tr(ctx, 'riskReasonHint')),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(ctx, 'cancel'))),
          FilledButton(key: const ValueKey('saveTier'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr(ctx, 'save'))),
        ],
      ),
    ),
  );
  if (saved != true || !context.mounted) return false;
  try {
    await RiskService.setTier(uid, picked, reason: reason.text);
    if (context.mounted) showSnack(context, tr(context, 'riskTierUpdated'));
    return true;
  } catch (error) {
    if (context.mounted) showSnack(context, errorText(context, error));
    return false;
  }
}

class _FlaggedUsersScreenState extends State<FlaggedUsersScreen> {
  late Future<List<FlaggedUser>> _future = RiskService.flagged();
  final _selected = <String>{};
  List<FlaggedUser> _list = const [];

  void _reload() => setState(() {
        _selected.clear();
        _future = RiskService.flagged();
      });

  /// F14: restrict the selected accounts in one go (admin confirms first).
  Future<void> _hold() async {
    final chosen = [for (final u in _list) if (_selected.contains(u.uid)) u];
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(trf(c, 'riskHoldConfirm', {'n': chosen.length})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr(c, 'cancel'))),
          FilledButton(key: const ValueKey('holdConfirm'), onPressed: () => Navigator.pop(c, true), child: Text(tr(c, 'save'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final n = await RiskService.bulkHold(chosen, reason: 'bulk hold (score)');
      if (mounted) showSnack(context, trf(context, 'riskHeld', {'n': n}));
      _reload();
    } catch (error) {
      if (mounted) showSnack(context, errorText(context, error));
    }
  }

  Future<void> _edit(FlaggedUser u) async {
    if (await editRiskTier(context, uid: u.uid, name: u.name.isEmpty ? maskPhone(u.phone) : u.name, tier: u.riskTier)) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'flaggedUsers'))),
      body: FutureBuilder<List<FlaggedUser>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return ErrorState(error: snap.error);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = _list = snap.data!;
          if (list.isEmpty) return EmptyState(icon: Icons.verified_user_outlined, title: tr(context, 'noFlaggedUsers'));
          return ListView(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Wrap(spacing: 8, children: [
                OutlinedButton(
                  key: const ValueKey('selectHold'),
                  onPressed: () => setState(() => _selected
                    ..clear()
                    ..addAll([for (final u in list) if (RiskRules.suggestHold(u.assessment.score) && u.riskTier != RiskTier.restricted && u.riskTier != RiskTier.suspended && u.riskTier != RiskTier.banned) u.uid])),
                  child: Text(tr(context, 'riskSelectSuggested')),
                ),
                if (_selected.isNotEmpty)
                  FilledButton(key: const ValueKey('holdSelected'), onPressed: _hold, child: Text(trf(context, 'riskHoldSelected', {'n': _selected.length}))),
              ]),
            ),
            for (final u in list)
              ListTile(
                key: ValueKey('flagged_${u.uid}'),
                leading: Checkbox(
                  key: ValueKey('flagPick_${u.uid}'),
                  value: _selected.contains(u.uid),
                  onChanged: (v) => setState(() => v == true ? _selected.add(u.uid) : _selected.remove(u.uid)),
                ),
                title: Text(u.name.isEmpty ? maskPhone(u.phone) : u.name),
                subtitle: Text([
                  riskTierLabel(context, u.riskTier),
                  trf(context, 'cancelsCount', {'n': u.cancelCount}),
                  trf(context, 'openReportsCount', {'n': u.openReports}),
                  trf(context, 'riskScoreN', {'n': u.assessment.score}),
                  if (RiskRules.suggestReview(u.assessment.score)) tr(context, 'riskSuggestReview'),
                  for (final r in u.assessment.reasons)
                    if (const ['booking_burst', 'booking_burst_warn', 'profile_changes', 'many_devices_24h', 'gps_mismatch'].contains(r)) tr(context, 'riskWhy_$r'),
                ].join(' · ')),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _edit(u),
              ),
          ]);
        },
      ),
    );
  }
}
