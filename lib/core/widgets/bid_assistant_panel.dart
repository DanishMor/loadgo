import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../pricing/bid_assistant.dart';
import 'common.dart';

/// Suggested bid with the reasons, in the price dialog (MASTER-6 Task 24).
class BidAssistantPanel extends StatelessWidget {
  final BidSuggestion suggestion;
  final void Function(int paise) onPick;
  const BidAssistantPanel({super.key, required this.suggestion, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final s = suggestion;
    Widget chip(String id, String key, int paise) => ActionChip(
          key: ValueKey('bidPick_$id'),
          label: Text(trf(context, key, {'a': formatPaise(paise)})),
          onPressed: () => onPick(paise),
        );
    String reason(BidReason r) => trf(context, r.key, {for (final e in r.args.entries) e.key: formatPaise(e.value as int)});
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr(context, 'bidSuggested'), style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Wrap(spacing: 8, runSpacing: 4, children: [chip('low', 'bidLow', s.low), chip('fair', 'bidFair', s.fair), chip('high', 'bidHigh', s.high)]),
      const SizedBox(height: 4),
      for (final r in s.reasons) Text(reason(r), key: ValueKey('bidWhy_${r.key}'), style: TextStyle(color: AppColors.muted, fontSize: 12)),
    ]);
  }
}
