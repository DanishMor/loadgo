import 'package:flutter/material.dart';

import '../../core/dispatch/dispatch_models.dart';
import '../../core/l10n/l10n.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/widgets/ds/app_button.dart';
import '../../core/widgets/ds/sheet_kit.dart';

/// What the sheet gives back: a rule to save, or null to turn the rule off.
class AutoAcceptChoice {
  final AutoAccept? rule;
  const AutoAcceptChoice(this.rule);
}

/// U14: the customer's auto-accept rule: the highest price, the lowest rating and "verified drivers only". It says
/// plainly that it works while the app is open.
class AutoAcceptSheet extends StatefulWidget {
  final AutoAccept? current;

  /// The highest price offered as a start, in rupees (usually the load's price).
  final int suggestRupees;

  const AutoAcceptSheet({super.key, this.current, required this.suggestRupees});

  @override
  State<AutoAcceptSheet> createState() => _AutoAcceptSheetState();
}

class _AutoAcceptSheetState extends State<AutoAcceptSheet> {
  late final _max = TextEditingController(text: '${(widget.current?.maxPaise ?? widget.suggestRupees * 100) ~/ 100}');
  late double _rating = widget.current?.minRating ?? 0;
  late bool _verified = widget.current?.verifiedOnly ?? false;
  String? _error;

  @override
  void dispose() {
    _max.dispose();
    super.dispose();
  }

  void _save() {
    final rupees = int.tryParse(_max.text.trim());
    if (rupees == null || rupees <= 0 || rupees * 100 > AutoAccept.maxAllowedPaise) {
      setState(() => _error = 'wzNeedPrice');
      return;
    }
    Navigator.of(context).pop(AutoAcceptChoice(AutoAccept(maxPaise: rupees * 100, minRating: _rating, verifiedOnly: _verified)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(tr(context, 'brAutoHint'), style: DsType.bodySmall.copyWith(color: c.textMuted)),
      const SizedBox(height: DsSpace.s4),
      TextField(
        key: const ValueKey('autoMax'),
        controller: _max,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: tr(context, 'brAutoMax'), prefixText: '₹ ', errorText: _error == null ? null : tr(context, _error!)),
        onChanged: (_) => setState(() => _error = null),
      ),
      const SizedBox(height: DsSpace.s4),
      Text(tr(context, 'brAutoRating'), style: DsType.label.copyWith(color: c.textMuted)),
      const SizedBox(height: DsSpace.s1),
      QuickChipRow<double>(
        padding: EdgeInsets.zero,
        options: [(0.0, tr(context, 'brAny')), (4.0, '4+'), (4.5, '4.5+')],
        selected: _rating,
        onChanged: (v) => setState(() => _rating = v ?? 0),
      ),
      SwitchListTile(
        key: const ValueKey('autoVerified'),
        contentPadding: EdgeInsets.zero,
        title: Text(tr(context, 'brVerifiedOnly')),
        value: _verified,
        onChanged: (v) => setState(() => _verified = v),
      ),
      const SizedBox(height: DsSpace.s2),
      AppButton(key: const ValueKey('autoSave'), label: tr(context, 'brSave'), big: true, onPressed: _save),
      if (widget.current != null) ...[
        const SizedBox(height: DsSpace.s2),
        AppButton(key: const ValueKey('autoOff'), label: tr(context, 'brAutoOff'), kind: AppButtonKind.tertiary, onPressed: () => Navigator.of(context).pop(const AutoAcceptChoice(null))),
      ],
    ]);
  }
}
