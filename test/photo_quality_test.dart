import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/photos/photo_quality.dart';

/// E18: on-device photo checks and metadata removal.
void main() {
  Uint8List flat(int v, int w, int h) => Uint8List(w * h)..fillRange(0, w * h, v);
  Uint8List checker(int w, int h, {int lo = 30, int hi = 220}) {
    final g = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        g[y * w + x] = ((x ~/ 4 + y ~/ 4).isEven) ? lo : hi;
      }
    }
    return g;
  }

  test('a flat grey picture is blurry; a dark one is dark; a white one is too bright', () {
    expect(PhotoQuality.fromGrey(flat(128, 64, 48), 64, 48).issues, [PhotoIssue.blurry]);
    expect(PhotoQuality.fromGrey(flat(10, 64, 48), 64, 48).issues, containsAll([PhotoIssue.tooDark, PhotoIssue.blurry]));
    expect(PhotoQuality.fromGrey(flat(250, 64, 48), 64, 48).issues, contains(PhotoIssue.tooBright));
  });

  test('sharp edges at normal light pass', () {
    final q = PhotoQuality.fromGrey(checker(64, 48), 64, 48);
    expect(q.ok, isTrue, reason: 'brightness ${q.brightness}, sharpness ${q.sharpness}');
  });

  test('a softened copy of the same picture scores lower', () {
    final sharp = checker(64, 48);
    final soft = Uint8List.fromList(sharp);
    for (var i = 1; i < soft.length - 1; i++) {
      soft[i] = ((sharp[i - 1] + sharp[i] + sharp[i + 1]) / 3).round();
    }
    expect(PhotoQuality.fromGrey(soft, 64, 48).sharpness, lessThan(PhotoQuality.fromGrey(sharp, 64, 48).sharpness));
  });

  test('bad sizes never throw', () {
    expect(PhotoQuality.fromGrey(Uint8List(0), 0, 0).ok, isFalse);
    expect(PhotoQuality.fromGrey(Uint8List(3), 10, 10).ok, isFalse);
    expect(PhotoQuality.grey(Uint8List.fromList([255, 255, 255, 255, 0, 0, 0, 255])), [255, 0]);
  });

  testWidgets('an undecodable file measures as not ok', (t) async {
    final q = await t.runAsync(() => PhotoQuality.measure(Uint8List.fromList([1, 2, 3])));
    expect(q!.ok, isFalse);
  });

  group('JPEG metadata', () {
    List<int> seg(int marker, List<int> body) => [0xFF, marker, (body.length + 2) >> 8, (body.length + 2) & 0xFF, ...body];
    final exif = seg(0xE1, [...'Exif'.codeUnits, 0, 0, ...'GPS 28.61 77.20 PhoneModel'.codeUnits]);
    final jfif = seg(0xE0, [...'JFIF'.codeUnits, 0, 1, 1]);
    final dqt = seg(0xDB, List.filled(65, 7));
    final com = seg(0xFE, 'made on a phone'.codeUnits);
    final scan = [0xFF, 0xDA, 0, 8, 1, 2, 3, 4, 5, 6, 0x12, 0x34, 0xFF, 0x00, 0x56, 0xFF, 0xD9];

    test('EXIF (GPS, phone model) and comments are removed; the picture and its tables stay', () {
      final file = Uint8List.fromList([0xFF, 0xD8, ...jfif, ...exif, ...com, ...dqt, ...scan]);
      final out = stripJpegMetadata(file);
      final text = String.fromCharCodes(out);
      expect(text.contains('GPS'), isFalse);
      expect(text.contains('made on a phone'), isFalse);
      expect(out, [0xFF, 0xD8, ...jfif, ...dqt, ...scan]);
    });

    test('a file that is not a JPEG, or a broken one, comes back untouched', () {
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
      expect(stripJpegMetadata(png), same(png));
      final broken = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE1, 0xFF, 0xFF, 1]);
      expect(stripJpegMetadata(broken), same(broken));
      final noScan = Uint8List.fromList([0xFF, 0xD8, ...jfif]);
      expect(stripJpegMetadata(noScan), same(noScan));
    });
  });
}
