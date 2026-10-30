import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/contrast.dart';
import '../../theme/design_tokens.dart';
import '../common.dart';

enum MoneySize {
  small(14, FontWeight.w600),
  body(16, FontWeight.w600),
  large(24, FontWeight.w700),
  display(32, FontWeight.w700);

  final double fontSize;
  final FontWeight weight;
  const MoneySize(this.fontSize, this.weight);
}

/// An amount of money from **integer paise**: "₹ 1,23,456" (Indian grouping,
/// ".50" only when there are paise), digits of equal width so a column lines up,
/// and always left to right, also inside Urdu and Kashmiri text.
///
/// * [hidden] shows "₹ ••••" and is read out as "Amount hidden" (the balance
///   privacy switch).
/// * [signed] puts + on credits and colours credits green and debits red (the
///   colours are moved to 4.5:1; the sign carries the meaning too).
/// * [strike] draws a line through it (the old price).
class MoneyText extends StatelessWidget {
  final int paise;
  final MoneySize size;
  final bool hidden;
  final bool signed;
  final bool strike;
  final Color? color;
  final TextAlign? align;

  const MoneyText(this.paise, {super.key, this.size = MoneySize.body, this.hidden = false, this.signed = false, this.strike = false, this.color, this.align});

  /// The text shown for [paise]; also used by screens that need the string.
  static String format(int paise, {bool hidden = false, bool signed = false}) {
    if (hidden) return '₹ ••••';
    final s = formatPaise(paise);
    return signed && paise > 0 ? '+$s' : s;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    var fg = color ?? c.text;
    if (signed && !hidden && color == null) {
      if (paise > 0) fg = ensureContrast(c.success, c.surface);
      if (paise < 0) fg = ensureContrast(c.error, c.surface);
    }
    final shown = format(paise, hidden: hidden, signed: signed);
    return Semantics(
      label: hidden ? tr(context, 'dsAmountHidden') : shown,
      excludeSemantics: true,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Text(
          shown,
          textAlign: align,
          style: DsType.number.copyWith(
            fontSize: size.fontSize,
            fontWeight: size.weight,
            color: fg,
            decoration: strike ? TextDecoration.lineThrough : null,
          ),
        ),
      ),
    );
  }
}

/// The eye button that hides or shows balances. Keep the choice in the screen
/// (default hidden for wallets) and pass it to [MoneyText.hidden].
class MoneyVisibilityButton extends StatelessWidget {
  final bool hidden;
  final ValueChanged<bool> onChanged;

  const MoneyVisibilityButton({super.key, required this.hidden, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tr(context, hidden ? 'dsShowAmount' : 'dsHideAmount'),
      icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
      onPressed: () => onChanged(!hidden),
    );
  }
}
