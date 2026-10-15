// Draws the launcher icon, the adaptive-icon foreground, the splash logo and
// the 512 px store icon from the same shapes as the in-app logo (LogoPainter).
//
//   flutter test tool/make_brand_assets_test.dart                     -> assets/branding
//   flutter test tool/make_brand_assets_test.dart --dart-define=OUT=C:\temp\icons
//
// It is a test only because it needs Flutter's drawing engine; it builds no app.
// Then:  dart run flutter_launcher_icons   and   dart run flutter_native_splash:create
// (docs/ICON_AND_SPLASH.md). These files are PLACEHOLDERS from the same mark as
// the app: the final logo comes from a designer.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/theme/design_tokens.dart';
import 'package:transport_app/core/widgets/ds/brand_logo.dart';

Future<void> png(String path, int size, void Function(ui.Canvas, ui.Size) draw) async {
  final rec = ui.PictureRecorder();
  draw(ui.Canvas(rec), ui.Size(size.toDouble(), size.toDouble()));
  final img = await rec.endRecording().toImage(size, size);
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
    expect(File('$out/icon.png').lengthSync(), greaterThan(1000));
  });
}
