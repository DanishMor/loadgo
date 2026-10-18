// Draws the key UX v2 components to PNG files with the real fonts, so that overlaps,
// cut text and ugly spacing can be looked at without a phone.
//
//   flutter test tool/render_kit_test.dart                                  -> build/ux_png
//   flutter test tool/render_kit_test.dart --dart-define=OUT=C:\temp\png
//
// It is a test only because it needs Flutter's drawing engine; it builds no app and
// opens no emulator. Each scene is 360 x 640 dp saved at 2x.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';

import '../test/ux2_kit_test.dart' as k;

Future<void> loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      l.addFont(rootBundle.load(f));
    }
    await l.load();
  }

  await load('Mukta', ['assets/fonts/mukta/Mukta-Regular.ttf', 'assets/fonts/mukta/Mukta-Bold.ttf']);
  await load('NotoSans', ['assets/fonts/NotoSans-Regular.ttf']);
  await load('NotoSansDevanagari', ['assets/fonts/NotoSansDevanagari-Regular.ttf']);
  await load('NotoSansTamil', ['assets/fonts/NotoSansTamil-Regular.ttf']);
  await load('NotoNaskhArabic', ['assets/fonts/NotoNaskhArabic-Regular.ttf']);
  final icons = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(File('${Platform.environment['FLUTTER_ROOT'] ?? 'C:/src/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytesSync())));
  await icons.load();
}

/// Renders [scene] and writes `<OUT>/<name>.png`. Other tools call this for their own screens.
Future<File> renderScene(WidgetTester t, String name, Widget scene, {double scale = 1.0, Brightness b = Brightness.light, AppLanguage lang = AppLanguage.english}) async {
  const out = String.fromEnvironment('OUT', defaultValue: 'build/ux_png');
  Directory(out).createSync(recursive: true);
  t.view.physicalSize = const Size(720, 1280);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  await t.pumpWidget(k.host(scene, scale: scale, b: b, lang: lang));
  await t.pump(const Duration(milliseconds: 400));
  final boundary = find.byType(RepaintBoundary).first.evaluate().first.renderObject! as RenderRepaintBoundary;
  late final File file;
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    file = File('$out/$name.png')..writeAsBytesSync(bytes.buffer.asUint8List());
  });
  return file;
}

void main() {
  testWidgets('draw the component kit', (t) async {
    await t.runAsync(loadFonts);
    final files = [
      await renderScene(t, 'kit_en_light', k.all()),
      await renderScene(t, 'kit_en_dark', k.all(), b: Brightness.dark),
      await renderScene(t, 'kit_hi_light_1.3x', k.all(), lang: AppLanguage.hindi, scale: 1.3),
      await renderScene(t, 'kit_ur_light_rtl', k.all(), lang: AppLanguage.urdu),
    ];
    for (final f in files) {
      expect(f.lengthSync(), greaterThan(2000), reason: f.path);
    }
  });
}
