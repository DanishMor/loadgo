import 'package:flutter/material.dart';

import 'common.dart';

class MiniBar {
  /// Short text under the bar (day number, month).
  final String label;
  final int value;

  /// Shown on long press / hover.
  final String tooltip;
  const MiniBar(this.label, this.value, this.tooltip);
}

/// Vertical bars made of plain containers (no chart package); the tallest
/// bar fills [height]. Bars with 0 stay a thin line. Keys: `{keyPrefix}_{i}`.
class MiniBars extends StatelessWidget {
  final List<MiniBar> bars;
  final double height;
  final String keyPrefix;

  /// Index drawn in the highlight colour (today, selected month).
  final int? highlight;

  const MiniBars({super.key, required this.bars, this.height = 90, this.keyPrefix = 'bar', this.highlight});

  @override
  Widget build(BuildContext context) {
    final peak = bars.fold<int>(0, (m, b) => b.value > m ? b.value : m);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        height: height,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < bars.length; i++)
            Expanded(
              child: Tooltip(
                message: bars[i].tooltip,
                child: Container(
                  key: ValueKey('${keyPrefix}_$i'),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  height: peak == 0 || bars[i].value == 0 ? 2 : 2 + (height - 2) * bars[i].value / peak,
                  decoration: BoxDecoration(
                    color: bars[i].value == 0 ? AppColors.border : (i == highlight ? AppColors.success : AppColors.primary),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 4),
      Row(children: [
        for (final b in bars)
          Expanded(child: Text(b.label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.clip, style: TextStyle(fontSize: 11, color: AppColors.muted))),
      ]),
    ]);
  }
}
