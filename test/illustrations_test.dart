import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/theme/design_tokens.dart';
import 'package:transport_app/core/widgets/ds/illustrations.dart';

/// E11: the original illustration set (empty, error, offline, success,
/// onboarding) is drawn in code in one style, in every colour set, with no
/// bitmap artwork in the app.
void main() {
  const sets = {'light': DsColors.light, 'dark': DsColors.dark, 'signature': DsColors.signature, 'midnight': DsColors.midnight};

  test('the set covers empty, error, offline, success, onboarding and notifications', () {
    expect(IllustrationKind.values, containsAll([
      IllustrationKind.emptyBox,
      IllustrationKind.error,
      IllustrationKind.noNetwork,
      IllustrationKind.success,
      IllustrationKind.onboardPost,
      IllustrationKind.onboardOffers,
      IllustrationKind.onboardTrack,
      IllustrationKind.noNotifications,
    ]));
  });

  for (final e in sets.entries) {
    test('every picture paints in ${e.key} at small and large sizes', () {
      for (final k in IllustrationKind.values) {
        for (final size in const [Size(80, 60), Size(320, 240)]) {
          final rec = ui.PictureRecorder();
          IllustrationPainter(k, e.value).paint(Canvas(rec), size);
          final pic = rec.endRecording();
          expect(pic, isNotNull, reason: '$k');
          pic.dispose();
        }
      }
    });
  }

  test('a painter repaints only when the picture or the colours change', () {
    const a = IllustrationPainter(IllustrationKind.onboardTrack, DsColors.signature);
    expect(a.shouldRepaint(const IllustrationPainter(IllustrationKind.onboardTrack, DsColors.signature)), isFalse);
    expect(a.shouldRepaint(const IllustrationPainter(IllustrationKind.onboardPost, DsColors.signature)), isTrue);
    expect(a.shouldRepaint(const IllustrationPainter(IllustrationKind.onboardTrack, DsColors.midnight)), isTrue);
  });

  test('pictures take every colour from the token set (no raw colours in the painter)', () {
    final src = File('lib/core/widgets/ds/illustrations.dart').readAsStringSync();
    expect(RegExp(r'Color\(0x').hasMatch(src), isFalse);
    expect(src.contains('Colors.'), isFalse);
  });

  test('no bitmap artwork is bundled (art is drawn in code)', () {
    final images = Directory('assets')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => RegExp(r'\.(png|jpe?g|webp|gif)$', caseSensitive: false).hasMatch(f.path))
        .where((f) => !f.path.replaceAll(r'\', '/').contains('assets/branding/'))
        .map((f) => f.path)
        .toList();
    expect(images, isEmpty, reason: 'store and icon files live in assets/branding only');
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(RegExp(r'^\s+- assets/(images|illustrations)', multiLine: true).hasMatch(pubspec), isFalse);
  });

  testWidgets('the view is decoration only and keeps 4:3 in every new kind', (t) async {
    for (final k in [IllustrationKind.onboardPost, IllustrationKind.onboardOffers, IllustrationKind.onboardTrack, IllustrationKind.noNotifications]) {
      await t.pumpWidget(MaterialApp(home: Center(child: IllustrationView(k, width: 240))));
      expect(t.getSize(find.byType(IllustrationView)), const Size(240, 180));
      expect(t.takeException(), isNull);
    }
  });
}
