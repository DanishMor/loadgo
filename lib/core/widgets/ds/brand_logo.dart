import 'package:flutter/material.dart';

import '../../app_info.dart';
import '../../theme/design_tokens.dart';

/// Which version of the mark to draw.
enum LogoVariant {
  /// Navy tile, white "L" with an arrow, saffron dot. For light backgrounds.
  tile,

  /// White tile, navy "L", saffron dot. For navy or dark backgrounds.
  reversed,

  /// Only the shapes (white "L" and arrow, saffron dot) on nothing, for the
  /// foreground layer of an adaptive launcher icon and the splash screen.
  foreground,

  /// One colour only (the [LogoMark.color]), for stamps, PDFs and one-colour print.
  mono,
}

/// The Load 20 mark: an "L" whose foot runs on into an arrow (a load on the
/// move) with a saffron dot above its corner (the place it is going to). Drawn
/// in code on a 100 x 100 grid, so it is sharp at every size, light and dark,
/// and needs no image file. The placeholder icon files are drawn from this same
/// shape (test/tool: `tool/make_brand_assets_test.dart`). The final logo is to
/// be approved by a designer (docs/BRAND.md).
class LogoMark extends StatelessWidget {
  final double size;
  final LogoVariant variant;

  /// Used by [LogoVariant.mono] only.
  final Color? color;

  const LogoMark({super.key, this.size = 48, this.variant = LogoVariant.tile, this.color});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Semantics(
      image: true,
      label: AppInfo.name,
      child: ExcludeSemantics(
        child: SizedBox(width: size, height: size, child: CustomPaint(painter: LogoPainter(variant, color: color ?? c.text))),
      ),
    );
  }
}

/// Paints the mark on a 100 x 100 grid scaled to the canvas.
class LogoPainter extends CustomPainter {
  final LogoVariant variant;
  final Color color;
  const LogoPainter(this.variant, {this.color = DsBrand.navy});

  /// The "L" with its arrow foot, as one outline: stem, foot, arrow head.
  static Path glyph() => Path()
    ..moveTo(27, 22)
    ..lineTo(41, 22)
    ..lineTo(41, 58)
    ..lineTo(68, 58)
    ..lineTo(68, 48)
    ..lineTo(88, 65)
    ..lineTo(68, 82)
    ..lineTo(68, 72)
    ..lineTo(27, 72)
    ..close();

  static const Offset dotCenter = Offset(63, 34);
  static const double dotRadius = 9;
  static const double tileRadius = 22;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    final fill = Paint()..style = PaintingStyle.fill..isAntiAlias = true;
    Color shape, dot;
    switch (variant) {
      case LogoVariant.tile:
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 100, 100), const Radius.circular(tileRadius)), fill..color = DsBrand.navy);
        shape = DsBrand.white;
        dot = DsBrand.saffron;
      case LogoVariant.reversed:
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 100, 100), const Radius.circular(tileRadius)), fill..color = DsBrand.white);
        shape = DsBrand.navy;
        dot = DsColors.light.accentStrong; // saffron is only 2:1 on white; the deeper amber is 5:1
      case LogoVariant.foreground:
        // Fit the shapes in the middle 66% of the canvas (the adaptive-icon safe zone).
        canvas.translate(50, 50);
        canvas.scale(0.72);
        canvas.translate(-57.5, -52);
        shape = DsBrand.white;
        dot = DsBrand.saffron;
      case LogoVariant.mono:
        shape = color;
        dot = color;
    }
    canvas.drawPath(glyph(), Paint()..color = shape..style = PaintingStyle.fill..isAntiAlias = true);
    canvas.drawCircle(dotCenter, dotRadius, Paint()..color = dot..style = PaintingStyle.fill..isAntiAlias = true);
    canvas.restore();
  }

  @override
  bool shouldRepaint(LogoPainter old) => old.variant != variant || old.color != color;
}

/// The name as a wordmark: "Load" in the text colour and "20" in saffron, set
/// in the brand font, bold. The size does not grow with the phone's text size
/// (a logo is a picture). Works for any name from [AppInfo.name]: a trailing
/// number is coloured, otherwise the whole name is one colour.
class Wordmark extends StatelessWidget {
  final double height;

  /// On a navy or dark background: white text, light saffron.
  final bool onDark;

  const Wordmark({super.key, this.height = 28, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final text = onDark ? DsBrand.white : c.text;
    final accent = onDark ? DsBrand.saffron : c.accentStrong;
    final name = AppInfo.name;
    final m = RegExp(r'^(.*?)(\s*)(\d+)$').firstMatch(name);
    final style = DsType.title.copyWith(fontSize: height, fontWeight: FontWeight.w700, height: 1.1, letterSpacing: -0.2);
    return MediaQuery.withNoTextScaling(
      child: Semantics(
        label: name,
        excludeSemantics: true,
        child: m == null
            ? Text(name, style: style.copyWith(color: text))
            : Text.rich(TextSpan(children: [
                TextSpan(text: '${m.group(1)}${m.group(2)}', style: style.copyWith(color: text)),
                TextSpan(text: m.group(3), style: style.copyWith(color: accent)),
              ])),
      ),
    );
  }
}

/// Mark and wordmark together: side by side ([vertical] false) or stacked.
class BrandLockup extends StatelessWidget {
  final double markSize;
  final bool vertical;
  final bool onDark;

  const BrandLockup({super.key, this.markSize = 48, this.vertical = false, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final mark = LogoMark(size: markSize, variant: onDark ? LogoVariant.reversed : LogoVariant.tile);
    final word = Wordmark(height: markSize * 0.6, onDark: onDark);
    final gap = SizedBox(width: markSize * 0.25, height: markSize * 0.2);
    return vertical
        ? Column(mainAxisSize: MainAxisSize.min, children: [mark, gap, word])
        : Row(mainAxisSize: MainAxisSize.min, children: [mark, gap, Flexible(child: word)]);
  }
}
