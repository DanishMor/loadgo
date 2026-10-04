import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/risk.dart';
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
      _ => 'riskNormal',
    });

class _FlaggedUsersScreenState extends State<FlaggedUsersScreen> {
  late Future<List<FlaggedUser>> _future = RiskService.flagged();

  void _reload() => setState(() => _future = RiskService.flagged());

  Future<void> _edit(FlaggedUser u) async {
    final reason = TextEditingController(text: '');
    var tier = u.riskTier;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(u.name.isEmpty ? u.phone : u.name),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            RadioGroup<String>(
              groupValue: tier,
              onChanged: (v) => setLocal(() => tier = v!),
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
    if (saved != true) return;
    try {
      await RiskService.setTier(u.uid, tier, reason: reason.text);
      if (!mounted) return;
      showSnack(context, tr(context, 'riskTierUpdated'));
      _reload();
    } catch (_) {
      if (mounted) showSnack(context, tr(context, 'somethingWrong'));
    }
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
