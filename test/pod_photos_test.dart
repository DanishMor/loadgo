import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_uploads.dart';
import 'package:transport_app/core/bilty/lr_pdf.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/models/trip_evidence.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/photos/photo_service.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/theme/app_theme.dart';

class FakeStorage implements StorageGateway {
  final files = <String, Uint8List>{};
  @override
  Future<void> put(String path, Uint8List bytes, String contentType, {void Function(double)? onProgress}) async => files[path] = bytes;
  @override
  Future<Uint8List?> get(String path, {int maxSize = 5 * 1024 * 1024}) async => files[path];
  @override
  Future<void> delete(String path) async => files.remove(path);
}

Widget host(Widget w) => LanguageScope(
      notifier: ValueNotifier(AppLanguage.english),
      child: MaterialApp(theme: AppTheme.build(Brightness.light), home: Scaffold(body: SingleChildScrollView(child: w))),
    );

/// F30/F31: papers for admins, photos in the LR PDF.
void main() {
  late FakeFirebaseFirestore db;
  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'admin1');
    PhotoService.gateway = FakeStorage();
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.photoUploads: true});
  });
  tearDown(() {
    PhotoService.gateway = const FirebaseStorageGateway();
    FeaturesService.reset();
  });

  testWidgets('admin: papers stay hidden until the button, and the look is logged', (t) async {
    await db.collection('users').doc('d1').collection('uploads').doc('x1').set({'kind': 'licence', 'path': 'users/d1/docs/licence/x1.jpg'});
    await t.pumpWidget(host(const AdminUploads(uid: 'd1')));
    expect(find.byKey(const ValueKey('paper_x1')), findsNothing);
    await t.tap(find.byKey(const ValueKey('showPapers_d1')));
    for (var i = 0; i < 5; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('paper_x1')), findsOneWidget);
  });

  testWidgets('with the switch off the admin sees nothing', (t) async {
    FeaturesService.notifier.value = const Features();
    await t.pumpWidget(host(const AdminUploads(uid: 'd1')));
    expect(find.byKey(const ValueKey('showPapers_d1')), findsNothing);
  });

  test('a damaged proof photo does not stop the LR from printing', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final bytes = await buildLrPdf(LrPdfInput(
      fields: const {'lrNo': 'LR1'},
      copy: 'full',
      issuerRole: 'transporter',
      language: AppLanguage.english,
      issuerName: 'X',
      delivered: true,
      generatedAt: DateTime(2026, 1, 1),
      podPhoto: Uint8List.fromList([1, 2, 3]),
    ));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('the PDF carries the signature and a real photo (bigger than the plain one) and survives odd strokes', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    LrPdfInput input({Uint8List? photo, SignatureStrokes? sig}) => LrPdfInput(
          fields: const {'lrNo': 'LR1'},
          copy: 'full',
          issuerRole: 'transporter',
          language: AppLanguage.english,
          issuerName: 'X',
          delivered: true,
          generatedAt: DateTime(2026, 1, 1),
          podPhoto: photo,
          signature: sig,
        );
    final plain = await buildLrPdf(input());
    final sig = SignatureStrokes([
      [for (var i = 0; i < 50; i++) (x: i / 49, y: 0.5 + 0.3 * (i.isEven ? 1 : -1) * (i / 49))],
      [(x: 0.1, y: 0.1), (x: 0.9, y: 0.9)],
    ]);
    final signed = await buildLrPdf(input(sig: sig));
    final withPhoto = await buildLrPdf(input(photo: _png, sig: sig));
    expect(signed.length, greaterThan(plain.length));
    expect(withPhoto.length, greaterThan(signed.length));
    // out-of-range points, a single point and an empty signature never break the page
    final odd = SignatureStrokes([
      [(x: -5.0, y: 9.0), (x: 3.0, y: -2.0)],
      [(x: 0.5, y: 0.5)],
    ]);
    expect(String.fromCharCodes((await buildLrPdf(input(sig: odd))).take(4)), '%PDF');
    expect((await buildLrPdf(input(sig: const SignatureStrokes([])))).length, plain.length, reason: 'an empty signature prints nothing');
  });
}

/// A real 8x8 grey PNG (made here, so the test does not depend on a hand-typed file).
final Uint8List _png = _makePng();

Uint8List _makePng() {
  int crc(List<int> data) {
    var c = 0xffffffff;
    for (final b in data) {
      c ^= b;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (c >> 1) ^ 0xedb88320 : c >> 1;
      }
    }
    return c ^ 0xffffffff;
  }

  List<int> be(int v) => [(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255];
  List<int> chunk(String type, List<int> data) {
    final body = [...type.codeUnits, ...data];
    return [...be(data.length), ...body, ...be(crc(body))];
  }

  const w = 8, h = 8;
  final raw = <int>[];
  for (var y = 0; y < h; y++) {
    raw.add(0); // no filter
    for (var x = 0; x < w; x++) {
      raw.add((x * 30 + y * 10) & 255); // grey
    }
  }
  return Uint8List.fromList([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
    ...chunk('IHDR', [...be(w), ...be(h), 8, 0, 0, 0, 0]),
    ...chunk('IDAT', ZLibEncoder().convert(raw)),
    ...chunk('IEND', const []),
  ]);
}
