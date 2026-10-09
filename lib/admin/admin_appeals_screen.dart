import 'package:flutter/material.dart';

import '../core/errors/friendly_error.dart';
import '../core/l10n/l10n.dart';
import '../core/services/strike_appeal_service.dart';
import '../core/widgets/common.dart';
import '../core/widgets/live_stream.dart';

/// Admin > Strike appeals (MASTER-6 Task 34): read the person's reason, then
/// take one strike off or keep it, with a short note the person sees.
class AdminAppealsScreen extends StatelessWidget {
  /// Test hooks.
  final Stream<List<StrikeAppeal>>? appeals;
  final Future<void> Function(StrikeAppeal, bool grant, String note)? decide;
  const AdminAppealsScreen({super.key, this.appeals, this.decide});

  Future<void> _decide(BuildContext context, StrikeAppeal a, bool grant) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr(c, grant ? 'apGrant' : 'apKeep')),
        content: TextField(key: const ValueKey('apNote'), controller: note, maxLength: 200, decoration: InputDecoration(labelText: tr(c, 'apNoteHint'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr(c, 'cancel'))),
          FilledButton(key: const ValueKey('apDecideOk'), onPressed: () => Navigator.pop(c, true), child: Text(tr(c, 'save'))),
        ],
      ),
    );
    final text = note.text;
    if (ok != true || !context.mounted) return;
    try {
      await (decide ?? ((x, g, n) => StrikeAppealService.decide(x, grant: g, note: n)))(a, grant, text);
    } catch (e) {
      if (context.mounted) showSnack(context, tr(context, FriendlyError.of(e)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'adminAppeals'))),
      body: LiveStream<List<StrikeAppeal>>(
        stream: () => appeals ?? StrikeAppealService.watchPending(),
        builder: (context, list) {
          if (list.isEmpty) return EmptyState(icon: Icons.task_alt_rounded, title: tr(context, 'apAdminNone'));
          return ListView(padding: const EdgeInsets.all(16), children: [
            for (final a in list)
              AppCard(
                key: ValueKey('appeal_${a.violationId}'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.violationId, style: const TextStyle(fontWeight: FontWeight.w800)),
                  if (a.createdAt != null) Text(formatDateTime(a.createdAt!), style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(a.text, key: ValueKey('appealText_${a.violationId}')),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    FilledButton(key: ValueKey('appealGrant_${a.violationId}'), onPressed: () => _decide(context, a, true), child: Text(tr(context, 'apGrant'))),
                    OutlinedButton(key: ValueKey('appealKeep_${a.violationId}'), onPressed: () => _decide(context, a, false), child: Text(tr(context, 'apKeep'))),
                  ]),
                ]),
              ),
          ]);
        },
      ),
    );
  }
}
