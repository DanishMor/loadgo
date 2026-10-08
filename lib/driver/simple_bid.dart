import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/voice/voice_input.dart';
import '../core/voice/voice_parser.dart';
import '../core/widgets/common.dart';

/// Step of the big +/- buttons: 100 rupees below 5,000, 500 above.
int simpleBidStep(int rupees) => rupees < 5000 ? 100 : 500;

/// Whole rupees after pressing + or - ([up] true = +). Never below the step
/// and never above the 10,00,000 limit used by the normal price field.
int simpleBidNext(int rupees, {required bool up}) {
  final step = up ? simpleBidStep(rupees) : simpleBidStep(rupees - 1);
  final next = up ? rupees + step : rupees - step;
  return next.clamp(step, 1000000);
}

/// Simple Mode price form: one big amount, +/- buttons, a mic and one
/// confirm button. Returns paise, or null when closed.
Future<int?> askSimpleBidPaise(BuildContext context, {int? initialPaise, Widget Function(BuildContext, int? paise)? footer}) =>
    showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.card,
      builder: (_) => _SimpleBidSheet(initialRupees: initialPaise == null ? 5000 : (initialPaise ~/ 100).clamp(100, 1000000), footer: footer),
    );

class _SimpleBidSheet extends StatefulWidget {
  final int initialRupees;
  final Widget Function(BuildContext, int? paise)? footer;
  const _SimpleBidSheet({required this.initialRupees, this.footer});

  @override
  State<_SimpleBidSheet> createState() => _SimpleBidSheetState();
}

class _SimpleBidSheetState extends State<_SimpleBidSheet> {
  late int _rupees = widget.initialRupees;

  void _heard(String text) {
    final n = VoiceParser.parseAmountRupees(text);
    if (n == null || n <= 0 || n > 1000000) {
      showSnack(context, tr(context, 'voiceNoAmount'));
      return;
    }
    setState(() => _rupees = n);
  }

  Widget _stepper(IconData icon, bool up, Key key) => SizedBox(
        width: 72,
        height: 72,
        child: IconButton.filledTonal(key: key, tooltip: tr(context, up ? 'a11yMore' : 'a11yLess'), iconSize: 40, onPressed: () => setState(() => _rupees = simpleBidNext(_rupees, up: up)), icon: Icon(icon)),
      );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr(context, 'yourPrice'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _stepper(Icons.remove_rounded, false, const ValueKey('bidMinus')),
                Expanded(
                  child: Text(formatRupees(_rupees),
                      key: const ValueKey('bidAmount'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w800)),
                ),
                _stepper(Icons.add_rounded, true, const ValueKey('bidPlus')),
              ],
            ),
            const SizedBox(height: 8),
            Center(child: VoiceMicButton(filled: true, onText: _heard)),
            if (widget.footer case final footer?) footer(context, _rupees * 100),
            const SizedBox(height: 12),
            SizedBox(
              height: 64,
              child: FilledButton(
                key: const ValueKey('bidConfirm'),
                onPressed: () => Navigator.of(context).pop(_rupees * 100),
                child: Text(tr(context, 'simpleSendPrice'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
