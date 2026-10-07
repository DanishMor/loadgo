import 'package:flutter/material.dart';

import '../constants/cancel_reasons.dart';
import '../l10n/l10n.dart';
import 'common.dart';

/// "Why are you cancelling?" as optional choice chips for a cancel dialog.
/// [by] is `customer` or `driver`; tapping the chosen chip again clears it.
class CancelReasonPicker extends StatefulWidget {
  final String by;
  final ValueChanged<String?> onChanged;

  const CancelReasonPicker({super.key, required this.by, required this.onChanged});

  @override
  State<CancelReasonPicker> createState() => _CancelReasonPickerState();
}

class _CancelReasonPickerState extends State<CancelReasonPicker> {
  String? _reason;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(tr(context, 'crTitle'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.title)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 0, children: [
        for (final code in CancelReasons.forRole(widget.by))
          ChoiceChip(
            key: ValueKey('cancelReason_$code'),
            label: Text(tr(context, CancelReasons.labelKey(code)), style: const TextStyle(fontSize: 12)),
            visualDensity: VisualDensity.compact,
            selected: _reason == code,
            onSelected: (on) {
              setState(() => _reason = on ? code : null);
              widget.onChanged(_reason);
            },
          ),
      ]),
    ]);
  }
}
