import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/lifecycle.dart';
import 'common.dart';

String lifecycleLabel(BuildContext context, LifecycleStage s) => tr(context, switch (s) {
      LifecycleStage.created => 'lcCreated',
      LifecycleStage.matched => 'lcMatched',
      LifecycleStage.confirmed => 'lcConfirmed',
      LifecycleStage.pickedUp => 'lcPickedUp',
      LifecycleStage.inTransit => 'lcInTransit',
      LifecycleStage.delivered => 'lcDelivered',
      LifecycleStage.settled => 'lcSettled',
      LifecycleStage.cancelled => 'lcCancelled',
    });

/// Posted -> offer picked -> confirmed -> picked up -> on the way -> delivered
/// -> paid, with the current step marked (P12).
class LifecycleBar extends StatelessWidget {
  final LifecycleStage stage;

  const LifecycleBar({super.key, required this.stage});

  @override
  Widget build(BuildContext context) {
    if (stage == LifecycleStage.cancelled) {
      return Align(alignment: Alignment.centerLeft, child: StatusChip(label: lifecycleLabel(context, stage), color: Colors.redAccent));
    }
    final at = lifecycleOrder.indexOf(stage);
    return SingleChildScrollView(
      key: const ValueKey('lifecycleBar'),
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final (i, s) in lifecycleOrder.indexed) ...[
          if (i > 0) Container(width: 14, height: 2, color: i <= at ? AppColors.primary : AppColors.border),
          Column(children: [
            Icon(i < at ? Icons.check_circle_rounded : (i == at ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded),
                size: 20, color: i <= at ? AppColors.primary : AppColors.faint),
            const SizedBox(height: 2),
            Text(lifecycleLabel(context, s),
                key: ValueKey('lc_${s.name}'),
                style: TextStyle(fontSize: 11, fontWeight: i == at ? FontWeight.w800 : FontWeight.w500, color: i <= at ? AppColors.title : AppColors.faint)),
          ]),
        ],
      ]),
    );
  }
}
