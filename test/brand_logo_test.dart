import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/app_info.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/theme/contrast.dart';
import 'package:transport_app/core/theme/design_tokens.dart';
import 'package:transport_app/core/widgets/ds/brand_logo.dart';

/// L13: the logo mark and wordmark.
const int px = 200; // render size

Future<ByteData> render(LogoVariant v, {Color color = DsBrand.navy}) async {
  final rec = ui.PictureRecorder();
  LogoPainter(v, color: color).paint(Canvas(rec), const Size(200, 200));
  final img = await rec.endRecording().toImage(px, px);
  return (await img.toByteData())!;
}

/// The colour at a point of the 100 x 100 design grid.
Color at(ByteData d, double x, double y) {
  final ix = (x * 2).round().clamp(0, px - 1), iy = (y * 2).round().clamp(0, px - 1);
  final o = (iy * px + ix) * 4;
  return Color.fromARGB(d.getUint8(o + 3), d.getUint8(o), d.getUint8(o + 1), d.getUint8(o + 2));
}

Widget host(Widget child, {Brightness b = Brightness.light, double scale = 1.0}) => MaterialApp(
      theme: AppTheme.build(b),
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('LogoMark geometry', () {
    test('the glyph sits inside the tile with a margin, and the dot inside the glyph box above the foot', () {
      final b = LogoPainter.glyph().getBounds();
      expect(b.left, greaterThanOrEqualTo(8));
      expect(b.top, greaterThanOrEqualTo(8));
      expect(b.right, lessThanOrEqualTo(92));
      expect(b.bottom, lessThanOrEqualTo(92));
      expect(LogoPainter.glyph().contains(LogoPainter.dotCenter), isFalse, reason: 'the dot is not inside the L');
      expect(LogoPainter.dotCenter.dy + LogoPainter.dotRadius, lessThan(58), reason: 'the dot floats above the foot of the L');
      expect(LogoPainter.dotCenter.dx - LogoPainter.dotRadius, greaterThan(41), reason: 'and clear of the stem');
    });

    test('the L, its foot and the arrow head are one solid shape', () {
      final g = LogoPainter.glyph();
      for (final p in const [Offset(34, 40), Offset(34, 65), Offset(55, 65), Offset(75, 65)]) {
        expect(g.contains(p), isTrue, reason: '$p');
      }
      for (final p in const [Offset(55, 40), Offset(15, 65), Offset(95, 65)]) {
        expect(g.contains(p), isFalse, reason: '$p');
      }
    });
  });

  group('LogoMark pixels', () {
    test('tile: navy tile with rounded corners, white glyph, saffron dot', () async {
      final d = await render(LogoVariant.tile);
      expect(at(d, 0.5, 0.5).a, 0, reason: 'the corner is rounded off');
      expect(at(d, 50, 50).toARGB32(), DsBrand.navy.toARGB32());
      expect(at(d, 34, 40).toARGB32(), DsBrand.white.toARGB32());
      expect(at(d, 63, 34).toARGB32(), DsBrand.saffron.toARGB32());
      expect(contrastRatio(DsBrand.white, DsBrand.navy), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(DsBrand.saffron, DsBrand.navy), greaterThanOrEqualTo(3.0));
    });

    test('reversed: white tile, navy glyph, a dot that is 3:1 on white', () async {
      final d = await render(LogoVariant.reversed);
      expect(at(d, 50, 90).toARGB32(), DsBrand.white.toARGB32());
      expect(at(d, 34, 40).toARGB32(), DsBrand.navy.toARGB32());
      final dot = at(d, 63, 34);
      expect(contrastRatio(dot, DsBrand.white), greaterThanOrEqualTo(3.0));
      expect(contrastRatio(DsBrand.navy, DsBrand.white), greaterThanOrEqualTo(4.5));
    });

    test('foreground: nothing behind the shapes, shapes inside the 66% safe zone', () async {
      final d = await render(LogoVariant.foreground);
      expect(at(d, 5, 5).a, 0);
      expect(at(d, 50, 90).a, 0);
      expect(at(d, 36, 52).toARGB32(), DsBrand.white.toARGB32());
      // Everything drawn stays within the middle 66% (17..83 of 100).
      var minX = px, minY = px, maxX = 0, maxY = 0;
      for (var y = 0; y < px; y++) {
        for (var x = 0; x < px; x++) {
          if (at(d, x / 2, y / 2).a > 0) {
            minX = minX < x ? minX : x;
            maxX = maxX > x ? maxX : x;
            minY = minY < y ? minY : y;
            maxY = maxY > y ? maxY : y;
          }
        }
      }
      expect(minX / 2, greaterThanOrEqualTo(17));
      expect(maxX / 2, lessThanOrEqualTo(83));
      expect(minY / 2, greaterThanOrEqualTo(17));
      expect(maxY / 2, lessThanOrEqualTo(83));
    });

    test('mono: every drawn pixel is the one colour', () async {
      const c = Color(0xFF336699);
      final d = await render(LogoVariant.mono, color: c);
      expect(at(d, 0.5, 0.5).a, 0, reason: 'no tile');
      expect(at(d, 34, 40).toARGB32(), c.toARGB32());
      expect(at(d, 63, 34).toARGB32(), c.toARGB32());
    });

    test('the painter repaints only on a change', () {
      expect(const LogoPainter(LogoVariant.tile).shouldRepaint(const LogoPainter(LogoVariant.tile)), isFalse);
      expect(const LogoPainter(LogoVariant.tile).shouldRepaint(const LogoPainter(LogoVariant.reversed)), isTrue);
      expect(const LogoPainter(LogoVariant.mono, color: DsBrand.navy).shouldRepaint(const LogoPainter(LogoVariant.mono, color: DsBrand.saffron)), isTrue);
    });
  });

  group('widgets', () {
    testWidgets('LogoMark has the requested size and is spoken as the app name', (t) async {
      final h = t.ensureSemantics();
      await t.pumpWidget(host(const LogoMark(size: 72)));
      expect(t.getSize(find.byType(LogoMark)), const Size(72, 72));
      expect(find.bySemanticsLabel(AppInfo.name), findsOneWidget);
      h.dispose();
    });

    testWidgets('Wordmark shows the name with the number apart, and ignores the text-size setting', (t) async {
      await t.pumpWidget(host(const Wordmark(height: 30)));
      final plain = t.getSize(find.byType(Wordmark));
      await t.pumpWidget(host(const Wordmark(height: 30), scale: 2.0));
      expect(t.getSize(find.byType(Wordmark)), plain, reason: 'a logo does not grow with big text');
      final rich = t.widget<RichText>(find.descendant(of: find.byType(Wordmark), matching: find.byType(RichText)).first);
      final spans = ((rich.text as TextSpan).children!.first as TextSpan).children!.cast<TextSpan>();
      expect(spans.length, 2);
      expect(spans[0].text, 'Load ');
      expect(spans[1].text, '20');
      expect(spans[1].style!.color, isNot(spans[0].style!.color));
    });

    for (final b in Brightness.values) {
      testWidgets('wordmark text is readable on its own background (${b.name})', (t) async {
        final c = DsColors.of(b);
        await t.pumpWidget(host(const Wordmark(), b: b));
        final rich = t.widget<RichText>(find.descendant(of: find.byType(Wordmark), matching: find.byType(RichText)).first);
        final spans = ((rich.text as TextSpan).children!.first as TextSpan).children!.cast<TextSpan>();
        expect(contrastRatio(spans[0].style!.color!, c.bg), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(spans[1].style!.color!, c.bg), greaterThanOrEqualTo(3.0));
      });
    }

    testWidgets('on dark: white text and the saffron number on navy', (t) async {
      await t.pumpWidget(host(const ColoredBox(color: DsBrand.navy, child: Padding(padding: EdgeInsets.all(8), child: Wordmark(onDark: true)))));
      final rich = t.widget<RichText>(find.descendant(of: find.byType(Wordmark), matching: find.byType(RichText)).first);
      final spans = ((rich.text as TextSpan).children!.first as TextSpan).children!.cast<TextSpan>();
      expect(contrastRatio(spans[0].style!.color!, DsBrand.navy), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(spans[1].style!.color!, DsBrand.navy), greaterThanOrEqualTo(3.0));
    });

    for (final vertical in [false, true]) {
      testWidgets('lockup fits 360 wide at 2.0x text, ${vertical ? 'stacked' : 'side by side'}', (t) async {
        t.view.physicalSize = const Size(360, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(host(BrandLockup(markSize: 64, vertical: vertical), scale: 2.0));
        expect(t.takeException(), isNull);
        expect(t.getSize(find.byType(BrandLockup)).width, lessThanOrEqualTo(360));
      });
    }

    testWidgets('lockup on dark uses the reversed mark', (t) async {
      await t.pumpWidget(host(const BrandLockup(onDark: true), b: Brightness.dark));
      final painter = t.widget<CustomPaint>(find.descendant(of: find.byType(LogoMark), matching: find.byType(CustomPaint)).first).painter! as LogoPainter;
      expect(painter.variant, LogoVariant.reversed);
    });
  });
}
