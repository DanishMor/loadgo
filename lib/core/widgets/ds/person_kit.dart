import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/contrast.dart';
import '../../theme/design_tokens.dart';
import 'money_text.dart';

/// E10: a round avatar with initials (or a photo the person gave), and a small
/// Verified tick only when [verified] is true (an admin checked them). The tint
/// comes from the name, so the same person always looks the same.
class AppAvatar extends StatelessWidget {
  final String name;
  final ImageProvider? image;
  final double size;
  final bool verified;

  const AppAvatar({super.key, required this.name, this.image, this.size = 40, this.verified = false});

  /// Up to two letters: first letters of the first and last word ("Ravi Kumar" -> "RK").
  static String initials(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    String first(String w) => String.fromCharCode(w.runes.first).toUpperCase();
    return words.length == 1 ? first(words.first) : first(words.first) + first(words.last);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final bg = name.hashCode.isEven ? c.tint : c.chip;
    final label = verified ? '$name, ${tr(context, 'dsVerified')}' : name;
    return Semantics(
      label: label,
      image: true,
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: size / 2,
              backgroundColor: bg,
              foregroundImage: image,
              child: Text(initials(name), maxLines: 1, style: DsType.label.copyWith(fontSize: size * 0.38, color: c.text, height: 1)),
            ),
            if (verified)
              PositionedDirectional(
                end: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle),
                  child: Icon(Icons.verified_rounded, size: size * 0.34, color: c.primary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// E10: read-only stars for a rating 0..5 with halves, an optional count, and
/// one spoken label ("4.5 out of 5"). The star colour is kept at 3:1 on the
/// surface in every look. Asking for a rating stays with StarRow (rating_widgets.dart).
class RatingStars extends StatelessWidget {
  final double value;
  final int? count;
  final double size;

  const RatingStars({super.key, required this.value, this.count, this.size = 16});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final v = value.isFinite ? value.clamp(0.0, 5.0) : 0.0;
    final star = ensureContrast(DsLegacy.star, c.surface, min: 3);
    final shown = v.toStringAsFixed(1);
    return Semantics(
      label: trf(context, 'dsRatingOf', {'n': shown}) + (count != null ? ' ($count)' : ''),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            Icon(
              v >= i ? Icons.star_rounded : (v >= i - 0.5 ? Icons.star_half_rounded : Icons.star_outline_rounded),
              size: size,
              color: star,
            ),
          const SizedBox(width: DsSpace.s1),
          Flexible(
            child: Text(
              count != null ? '$shown ($count)' : shown,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DsType.numberSmall.copyWith(color: c.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// E10: a price as people should read it: a small label, the amount in large
/// equal-width digits, an optional fair range under it and a "tax included"
/// note. Amounts are integer paise; nothing here rounds or converts.
class PriceDisplay extends StatelessWidget {
  final int paise;
  final String? label;
  final int? lowPaise;
  final int? highPaise;
  final bool taxIncluded;
  final MoneySize size;

  const PriceDisplay({super.key, required this.paise, this.label, this.lowPaise, this.highPaise, this.taxIncluded = false, this.size = MoneySize.large});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final range = lowPaise != null && highPaise != null && lowPaise! <= highPaise!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) Text(label!, style: DsType.caption.copyWith(color: c.textMuted)),
        MoneyText(paise, size: size),
        if (range)
          Text(
            trf(context, 'dsPriceRange', {'a': MoneyText.format(lowPaise!), 'b': MoneyText.format(highPaise!)}),
            style: DsType.numberSmall.copyWith(color: c.textMuted),
          ),
        if (taxIncluded) Text(tr(context, 'dsTaxIncluded'), style: DsType.caption.copyWith(color: c.textMuted)),
      ],
    );
  }
}
