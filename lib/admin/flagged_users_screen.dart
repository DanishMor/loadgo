import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/risk.dart';
import '../core/risk/risk_rules.dart';
import '../core/services/risk_service.dart';
import '../core/widgets/common.dart';

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
  } catch (_) {
    if (context.mounted) showSnack(context, tr(context, 'somethingWrong'));
    return false;
  }
}

class _FlaggedUsersScreenState extends State<FlaggedUsersScreen> {
  late Future<List<FlaggedUser>> _future = RiskService.flagged();

  void _reload() => setState(() {
        _future = RiskService.flagged();
      });

  Future<void> _edit(FlaggedUser u) async {
    if (await editRiskTier(context, uid: u.uid, name: u.name.isEmpty ? u.phone : u.name, tier: u.riskTier)) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'flaggedUsers'))),
      body: FutureBuilder<List<FlaggedUser>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text(tr(context, 'somethingWrong')));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!;
          if (list.isEmpty) return Center(child: Text(tr(context, 'noFlaggedUsers')));
          return ListView(children: [
            for (final u in list)
              ListTile(
                key: ValueKey('flagged_${u.uid}'),
                title: Text(u.name.isEmpty ? u.phone : u.name),
                subtitle: Text([
                  riskTierLabel(context, u.riskTier),
                  trf(context, 'cancelsCount', {'n': u.cancelCount}),
                  trf(context, 'openReportsCount', {'n': u.openReports}),
                  trf(context, 'riskScoreN', {'n': u.assessment.score}),
                  if (RiskRules.suggestReview(u.assessment.score)) tr(context, 'riskSuggestReview'),
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
