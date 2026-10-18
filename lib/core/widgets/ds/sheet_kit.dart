import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/design_tokens.dart';
import 'skeleton.dart';

/// The one bottom sheet of the app's new screens: a drag handle, a title, the content in
/// a scroll view that keeps clear of the keyboard, and a Close button for screen readers.
/// Returns what the content passes to `Navigator.pop`.
Future<R?> showAppSheet<R>(BuildContext context, {required String title, required Widget child, bool dismissible = true}) {
  return showModalBottomSheet<R>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    showDragHandle: true,
    builder: (ctx) => AppSheetBody(title: title, child: child),
  );
}

class AppSheetBody extends StatelessWidget {
  final String title;
  final Widget child;
  const AppSheetBody({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(DsSpace.gutter, 0, DsSpace.gutter, DsSpace.s5),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: Semantics(header: true, child: Text(title, style: DsType.title.copyWith(color: c.textStrong)))),
            IconButton(tooltip: tr(context, 'uxClose'), icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(context).maybePop()),
          ]),
          const SizedBox(height: DsSpace.s2),
          child,
        ]),
      ),
    );
  }
}

/// One row of quick choices (goods, ETA, note, sort). One chip can be selected; tapping the
/// selected one again clears it when [clearable]. Scrolls sideways, chips at least 48 dp tall.
class QuickChipRow<V> extends StatelessWidget {
  final List<(V value, String label)> options;
  final V? selected;
  final ValueChanged<V?> onChanged;
  final bool clearable;

  const QuickChipRow({super.key, required this.options, required this.selected, required this.onChanged, this.clearable = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: DsSpace.tapMin + DsSpace.s2,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: DsSpace.gutter),
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
