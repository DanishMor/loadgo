import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';
import 'skeleton.dart';

/// One row of quick choices (goods, ETA, note, sort). One chip can be selected; tapping the
/// selected one again clears it when [clearable]. Scrolls sideways, chips at least 48 dp tall.
class QuickChipRow<V> extends StatelessWidget {
  final List<(V value, String label)> options;
  final V? selected;
  final ValueChanged<V?> onChanged;
  final bool clearable;

  /// Space at both ends of the row; zero when the row already sits inside a padded page.
  final EdgeInsetsGeometry padding;

  const QuickChipRow({super.key, required this.options, required this.selected, required this.onChanged, this.clearable = false, this.padding = const EdgeInsets.symmetric(horizontal: DsSpace.gutter)});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: DsSpace.tapMin + DsSpace.s2,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: DsSpace.s2),
        itemBuilder: (context, i) {
          final (value, label) = options[i];
          final on = value == selected;
          return Center(
            child: ChoiceChip(
              key: ValueKey('chip_$i'),
              label: Text(label),
              selected: on,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              onSelected: (_) => onChanged(on && clearable ? null : value),
            ),
          );
        },
      ),
    );
  }
}

/// Grey placeholders for a list of cards while data loads.
class SkeletonList extends StatelessWidget {
  final int count;
  const SkeletonList({super.key, this.count = 3});

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: Column(children: [
        for (var i = 0; i < count; i++) ...[
          const SkeletonCard(),
          const SizedBox(height: DsSpace.s3),
        ],
      ]),
    );
  }
}
