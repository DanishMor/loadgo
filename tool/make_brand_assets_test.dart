// Draws the launcher icon, the adaptive-icon foreground and monochrome layers, the splash logo,
// the 512 px store icon and the 1024 x 500 feature graphic from the same shapes as the in-app logo
// (LogoPainter). Sizes and store rules: docs/STORE_ASSETS.md.
//
//   flutter test tool/make_brand_assets_test.dart                     -> assets/branding
//   flutter test tool/make_brand_assets_test.dart --dart-define=OUT=C:\temp\icons
//
// It is a test only because it needs Flutter's drawing engine; it builds no app.
// Then:  dart run flutter_launcher_icons   and   dart run flutter_native_splash:create
// (docs/ICON_AND_SPLASH.md). The feature graphic goes to build/store (STORE): it is not bundled into the app. These files are PLACEHOLDERS from the same mark as
// the app: the final logo comes from a designer.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/theme/design_tokens.dart';
import 'package:transport_app/core/widgets/ds/brand_logo.dart';

Future<void> png(String path, int size, void Function(ui.Canvas, ui.Size) draw, {int? height}) async {
  final rec = ui.PictureRecorder();
  final h = height ?? size;
  draw(ui.Canvas(rec), ui.Size(size.toDouble(), h.toDouble()));
  final img = await rec.endRecording().toImage(size, h);
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
  File(path).writeAsBytesSync(bytes.buffer.asUint8List());
}

void main() {
  test('draw the brand assets', () async {
    const out = String.fromEnvironment('OUT', defaultValue: 'assets/branding');
    Directory(out).createSync(recursive: true);
    void navy(ui.Canvas c, ui.Size s) => c.drawRect(ui.Offset.zero & s, ui.Paint()..color = DsBrand.navy);

    // Legacy / iOS icon: a full navy square (the platform rounds it), mark in the middle.
    await png('$out/icon.png', 1024, (c, s) {
      navy(c, s);
      const LogoPainter(LogoVariant.foreground).paint(c, s);
    });
    // Android adaptive icon: the mark alone, inside the safe zone; the background is navy (pubspec).
    await png('$out/icon_foreground.png', 1024, (c, s) => const LogoPainter(LogoVariant.foreground).paint(c, s));
    // Native splash: the mark on the navy splash colour (pubspec).
    await png('$out/splash_logo.png', 1024, (c, s) => const LogoPainter(LogoVariant.foreground).paint(c, s));
    // Play Store listing icon (512 x 512).
    await png('$out/store_icon_512.png', 512, (c, s) {
      navy(c, s);
      const LogoPainter(LogoVariant.foreground).paint(c, s);
    });
    // Android 13 themed icon: the mark in one colour on nothing, in the same safe zone as the foreground
    // (the launcher tints it; only the alpha counts).
    await png('$out/icon_monochrome.png', 1024, (c, s) {
      c.translate(s.width / 2, s.height / 2);
      c.scale(0.72);
      c.translate(-0.575 * s.width, -0.52 * s.height);
      const LogoPainter(LogoVariant.mono, color: DsBrand.white).paint(c, s);
    });
    // Play feature graphic: opaque Navy-to-Ink, the mark in the middle, no words (it is cropped in places).
    const store = String.fromEnvironment('STORE', defaultValue: 'build/store');
    Directory(store).createSync(recursive: true);
    await png('$store/feature_graphic_1024x500.png', 1024, height: 500, (c, s) {
      c.drawRect(ui.Offset.zero & s, ui.Paint()..shader = ui.Gradient.linear(ui.Offset.zero, ui.Offset(s.width, s.height), const [DsLuxe.navy, DsLuxe.ink]));
      const mark = 300.0;
      c.translate((s.width - mark) / 2, (s.height - mark) / 2);
      const LogoPainter(LogoVariant.foreground).paint(c, const ui.Size(mark, mark));
    });
    expect(File('$out/icon.png').lengthSync(), greaterThan(1000));
    expect(File('$out/icon_monochrome.png').lengthSync(), greaterThan(1000));
    expect(File('$store/feature_graphic_1024x500.png').lengthSync(), greaterThan(1000));
  });
}
