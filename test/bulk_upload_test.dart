import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/enterprise/bulk_loads.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/customer/bulk_post_screen.dart';

const types = ['14ft', '20ft'];

/// E29: bulk post from Excel or CSV (flag bulkUpload).
void main() {
  setUp(() {
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'c1');
    FeaturesService.reset();
    languageNotifier.value = AppLanguage.english;
  });
  tearDown(FeaturesService.reset);

  test('CSV cells: quotes keep separators, doubled quotes, tabs and semicolons', () {
    expect(splitCsvLine('"Bhiwandi, Thane",Surat,"Said ""fragile""",5'), ['Bhiwandi, Thane', 'Surat', 'Said "fragile"', '5']);
    expect(splitCsvLine('Pune\tMumbai\tFMCG\t3\t14ft'), ['Pune', 'Mumbai', 'FMCG', '3', '14ft']);
    expect(splitCsvLine('Pune;Mumbai;FMCG;3;14ft;'), ['Pune', 'Mumbai', 'FMCG', '3', '14ft', '']);
  });

  test('v2 drops the byte-order mark and the header row; line numbers stay those of the text', () {
    final r = parseBulkLoads('﻿$bulkHeader\r\n"Bhiwandi, Thane",Surat,Textile,5.5,20ft,\r\nX,Pune,FMCG,3,14ft', vehicleTypeIds: types, v2: true);
    expect(r.rows.single.pickup, 'Bhiwandi, Thane');
    expect(r.rows.single.line, 2);
    expect(r.errors.single.line, 3);
    expect(r.errors.single.error, BulkError.place);
  });

  test('the template parses clean with v2; without v2 the old paste rules are unchanged', () {
    final r = parseBulkLoads(bulkTemplate(types), vehicleTypeIds: types, v2: true);
    expect(r.ok, isTrue);
    expect(r.rows.length, 2);
    final old = parseBulkLoads('Delhi, Mumbai, FMCG, 8, 20ft, 25000', vehicleTypeIds: types);
    expect(old.ok, isTrue);
    expect(parseBulkLoads(bulkTemplate(types), vehicleTypeIds: types).ok, isFalse, reason: 'old mode does not skip a header');
  });

  Widget host() => LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: BulkPostScreen()));

  testWidgets('screen: template, paste, preview and reasons only with bulkUpload on', (t) async {
    await t.pumpWidget(host());
    expect(find.byKey(const ValueKey('bulkCopyTemplate')), findsNothing);

    FeaturesService.notifier.value = const Features(flags: {FeatureKey.bulkUpload: true});
    String? clip;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clip = (call.arguments as Map)['text'] as String;
      if (call.method == 'Clipboard.getData') return {'text': '$bulkHeader\nPune,Mumbai,FMCG,3,14ft,18000\nPune,,FMCG,3,14ft'};
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(host());
    await t.tap(find.byKey(const ValueKey('bulkCopyTemplate')));
    await t.pumpAndSettle();
    expect(clip, startsWith(bulkHeader));
    await t.tap(find.byKey(const ValueKey('bulkPaste')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('bulkRow_2')), findsOneWidget);
    expect(find.textContaining(T.get('bulkWhy_place', AppLanguage.english)), findsOneWidget);
  });
}
