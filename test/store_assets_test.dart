import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// E14: launcher, themed (monochrome) and splash variants are wired and drawn from the brand mark
/// (tool/make_brand_assets_test.dart, docs/STORE_ASSETS.md).
void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();

  test('the adaptive icon has a monochrome layer for Android 13 themed icons', () {
    expect(pubspec, contains('adaptive_icon_monochrome: assets/branding/icon_monochrome.png'));
    final xml = File('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml').readAsStringSync();
    expect(xml, contains('<monochrome>'));
    expect(xml, contains('@drawable/ic_launcher_monochrome'));
    for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      expect(File('android/app/src/main/res/drawable-$d/ic_launcher_monochrome.png').existsSync(), isTrue, reason: d);
    }
  });

  test('the splash is Navy by day and true black at night (the first frame of Midnight)', () {
    final splash = pubspec.substring(pubspec.indexOf(RegExp(r'^flutter_native_splash:', multiLine: true)));
    expect(RegExp(r'color_dark: "#000000"').allMatches(splash).length, 2, reason: 'classic splash and Android 12');
    expect(RegExp(r'color: "#123A6B"').allMatches(splash).length, 2);
    expect(File('android/app/src/main/res/values-night-v31/styles.xml').readAsStringSync(), contains('#000000'));
  });

  testWidgets('the monochrome icon is one colour on nothing and keeps the mark inside the 66% safe zone', (t) async {
    final bytes = File('assets/branding/icon_monochrome.png').readAsBytesSync();
    late ui.Image img;
    late List<int> px;
    await t.runAsync(() async {
      final codec = await ui.instantiateImageCodec(bytes);
      img = (await codec.getNextFrame()).image;
      px = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
    });
    expect(img.width, 1024);
    final colours = <int>{};
    var minX = img.width, maxX = 0, minY = img.height, maxY = 0;
    for (var y = 0; y < img.height; y++) {
      for (var x = 0; x < img.width; x++) {
        final i = (y * img.width + x) * 4;
        if (px[i + 3] < 255) continue; // edge anti-aliasing is fine
        colours.add((px[i] << 16) | (px[i + 1] << 8) | px[i + 2]);
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
    // one colour: every solid pixel is white (rounding at the edges may move a channel by a step or two)
    expect(colours.every((c) => (c >> 16 & 255) > 250 && (c >> 8 & 255) > 250 && (c & 255) > 250), isTrue, reason: colours.map((c) => c.toRadixString(16)).join(','));
    const safe = 1024 * 0.17; // the 66% safe zone leaves 17% on each side
    expect(minX, greaterThan(safe));
    expect(minY, greaterThan(safe));
    expect(maxX, lessThan(1024 - safe));
    expect(maxY, lessThan(1024 - safe));
  });

  test('the store guide lists every file the generator writes', () {
    final doc = File('docs/STORE_ASSETS.md').readAsStringSync();
    for (final f in ['store_icon_512.png', 'feature_graphic_1024x500.png', 'icon_foreground.png', 'icon_monochrome.png', 'splash_logo.png', 'icon.png']) {
      expect(doc, contains(f));
    }
    expect(doc, contains('UNVERIFIED'));
  });
}
