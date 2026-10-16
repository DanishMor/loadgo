import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_uploads.dart';
import 'package:transport_app/core/bilty/lr_pdf.dart';
import 'package:transport_app/core/features/features.dart';
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
}
