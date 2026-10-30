import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import '../l10n/l10n.dart';
import '../theme/design_tokens.dart';
import '../widgets/ds/app_button.dart';
import 'home_layout.dart';

/// E21: lets a person reorder and hide home sections. Drag the handle, or with TalkBack use the "Move up" and
/// "Move down" actions of a row. Returns the new layout, or null when dismissed. [labels] maps a section id to its
/// words key; [defaults] is what Reset goes back to.
Future<HomeLayout?> showHomeCustomizeSheet(
  BuildContext context, {
  required HomeLayout layout,
  required HomeLayout defaults,
  required Map<String, String> labels,
}) => showModalBottomSheet<HomeLayout>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => HomeCustomizeSheet(layout: layout, defaults: defaults, labels: labels),
);

class HomeCustomizeSheet extends StatefulWidget {
  final HomeLayout layout;
  final HomeLayout defaults;
  final Map<String, String> labels;
  const HomeCustomizeSheet({super.key, required this.layout, required this.defaults, required this.labels});

  @override
  State<HomeCustomizeSheet> createState() => _HomeCustomizeSheetState();
}

class _HomeCustomizeSheetState extends State<HomeCustomizeSheet> {
  late HomeLayout _layout = widget.layout;

  void _move(int from, int to) => setState(() => _layout = _layout.move(from, to));

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final order = _layout.order;
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: DsSpace.gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(tr(context, 'hlCustomize'), style: DsType.title.copyWith(color: c.textStrong)),
                  ),
                  const SizedBox(height: DsSpace.s1),
                  Text(tr(context, 'hlHint'), style: DsType.bodySmall.copyWith(color: c.textMuted)),
                ],
              ),
            ),
            const SizedBox(height: DsSpace.s2),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: order.length,
              onReorderItem: _move,
              itemBuilder: (context, i) {
                final id = order[i];
                final locked = _layout.locked.contains(id);
                final label = tr(context, widget.labels[id] ?? id);
                return Semantics(
                  key: ValueKey('hl_$id'),
                  customSemanticsActions: {
                    if (i > 0) CustomSemanticsAction(label: tr(context, 'hlMoveUp')): () => _move(i, i - 1),
                    if (i < order.length - 1) CustomSemanticsAction(label: tr(context, 'hlMoveDown')): () => _move(i, i + 1),
                  },
                  child: Material(
                    color: Colors.transparent,
                    child: Row(
                      children: [
                        ReorderableDragStartListener(
                          index: i,
                          child: SizedBox(width: 48, height: 48, child: Icon(Icons.drag_indicator_rounded, color: c.textMuted)),
                        ),
                        Expanded(
                          child: SwitchListTile(
                            key: ValueKey('hlSwitch_$id'),
                            contentPadding: const EdgeInsetsDirectional.only(end: DsSpace.gutter),
                            title: Text(label, style: DsType.body.copyWith(color: c.text)),
                            subtitle: locked ? Text(tr(context, 'hlAlways'), style: DsType.caption.copyWith(color: c.textMuted)) : null,
                            value: !_layout.isHidden(id),
                            onChanged: locked ? null : (_) => setState(() => _layout = _layout.toggle(id)),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(DsSpace.gutter, DsSpace.s2, DsSpace.gutter, DsSpace.gutter),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: DsSpace.s2,
                runSpacing: DsSpace.s2,
                children: [
                  TextButton(key: const ValueKey('hlReset'), onPressed: () => setState(() => _layout = widget.defaults), child: Text(tr(context, 'hlReset'))),
                  AppButton(key: const ValueKey('hlDone'), label: tr(context, 'hlDone'), onPressed: () => Navigator.pop(context, _layout)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
