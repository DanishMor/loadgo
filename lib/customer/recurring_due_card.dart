import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/recurring.dart';
import '../core/services/recurring_service.dart';
import '../core/widgets/common.dart';
import 'post_load_screen.dart';

/// Home: repeating loads that came due. "Post now" opens Post Load filled in;
/// "Skip" moves to the next date. Hidden when nothing is due.
class RecurringDueCard extends StatefulWidget {
  final Stream<List<RecurringLoad>>? source;
  final DateTime Function()? clock;

  const RecurringDueCard({super.key, this.source, this.clock});

  @override
  State<RecurringDueCard> createState() => _RecurringDueCardState();
}

class _RecurringDueCardState extends State<RecurringDueCard> {
  late final Stream<List<RecurringLoad>> _stream = (widget.source ?? RecurringService.watch()).asBroadcastStream();

  Future<void> _post(RecurringLoad r) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => PostLoadScreen(repostFrom: r.toDraft(), recurring: r, dueDate: r.nextDueAt)));

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RecurringLoad>>(
      stream: _stream,
      builder: (context, snap) {
        final now = (widget.clock ?? DateTime.now)();
        final due = [for (final r in snap.data ?? const <RecurringLoad>[]) if (r.isDue(now)) r];
        if (due.isEmpty) return const SizedBox.shrink();
        return Column(children: [
          for (final r in due)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: AppCard(
                key: ValueKey('recurringDue_${r.id}'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.repeat_rounded, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(tr(context, 'repeatDueTitle'), style: const TextStyle(fontWeight: FontWeight.w800))),
                  ]),
                  const SizedBox(height: 4),
                  Text('${r.template.pickup} → ${r.template.drop}', style: TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    FilledButton(key: ValueKey('recurringPost_${r.id}'), onPressed: () => _post(r), child: Text(tr(context, 'repeatPostNow'))),
                    OutlinedButton(key: ValueKey('recurringSkip_${r.id}'), onPressed: () => RecurringService.advance(r, from: r.nextDueAt), child: Text(tr(context, 'repeatSkip'))),
                    TextButton(key: ValueKey('recurringStop_${r.id}'), onPressed: () => RecurringService.delete(r.id), child: Text(tr(context, 'repeatStop'))),
                  ]),
                ]),
              ),
            ),
        ]);
      },
    );
  }
}
