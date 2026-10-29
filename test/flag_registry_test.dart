import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_features_screen.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/l10n/strings.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';

import 'test_utils.dart';

/// E3: the flag registry, docs/FLAGS.md and the entry-point guard.
void main() {
  final doc = File('docs/FLAGS.md').readAsStringSync();
  final registered = {for (final s in Features.registry) s.key: s};

  List<String>? strings(String key) {
    for (final t in stringTables) {
      if (t.containsKey(key)) return t[key];
    }
    return null;
  }

  /// Rows of the "Elite flags" table: flag, phase, status, group, default, depends, risk, entry points.
  final elite = <List<String>>[
    for (final line in doc.split(RegExp(r'\r?\n')).skipWhile((l) => !l.startsWith('## Elite flags')))
      if (RegExp(r'^\| `\w+` \| E\d+').hasMatch(line)) line.split('|').map((c) => c.trim()).where((c) => c.isNotEmpty).toList(),
  ];

  test('every flag has a known group and is listed in docs/FLAGS.md', () {
    for (final s in Features.registry) {
      expect(FeatureGroup.all, contains(s.group), reason: s.key);
      expect(doc.contains('| `${s.key}` |'), isTrue, reason: '${s.key} is missing from docs/FLAGS.md');
    }
  });

  test('every group heading and every flag has text in all 12 languages', () {
    final keys = [
      for (final g in FeatureGroup.all) 'featGroup_$g',
      for (final s in Features.registry) ...['feat_${s.key}', 'featHelp_${s.key}'],
    ];
    for (final k in keys) {
      final v = strings(k);
      expect(v, isNotNull, reason: k);
      expect(v!.length, 12, reason: k);
      expect(v.every((s) => s.trim().isNotEmpty), isTrue, reason: k);
    }
  });

  test('legal gates sit in the Legal group and are OFF in every mode', () {
    for (final s in Features.registry) {
      final gate = s.key.startsWith('legalGate');
      expect(s.group == FeatureGroup.legal, gate, reason: s.key);
      if (gate) {
        expect(s.pilotOn || s.normalOn, isFalse, reason: s.key);
      }
    }
  });

  test('the Elite table is complete and parsed', () {
    expect(elite.length, greaterThan(40));
    for (final row in elite) {
      expect(row.length, 8, reason: row.join(' | '));
      expect(['planned', 'live'], contains(row[2]), reason: row[0]);
      expect(FeatureGroup.all, contains(row[3]), reason: row[0]);
    }
  });

  test('planned Elite flags are not reachable; live ones default OFF and every entry point checks its flag', () {
    for (final row in elite) {
      final key = row[0].replaceAll('`', '');
      if (row[2] == 'planned') {
        expect(registered.containsKey(key), isFalse, reason: '$key is registered but still planned in docs/FLAGS.md');
        continue;
      }
      final spec = registered[key];
      expect(spec, isNotNull, reason: '$key is live in docs/FLAGS.md but not in Features.registry');
      expect(spec!.group, row[3], reason: key);
      final defaultOn = key == 'designV3';
      expect(spec.pilotOn, defaultOn, reason: key);
      expect(spec.normalOn, defaultOn, reason: key);
      final files = RegExp(r'`([^`]+\.dart)`').allMatches(row[7]).map((m) => m.group(1)!).toList();
      expect(files, isNotEmpty, reason: '$key has no entry points in docs/FLAGS.md');
      for (final f in files) {
        expect(File(f).readAsStringSync(), contains('FeatureKey.$key'), reason: '$f does not check $key');
      }
    }
  });

  testWidgets('Admin > Features shows a heading per non-empty group', (t) async {
    languageNotifier.value = AppLanguage.english;
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'admin1');
    FeaturesService.reset();
    t.view.physicalSize = const Size(800, 12000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: LanguageScope(notifier: languageNotifier, child: const AdminFeaturesScreen())));
    await settle(t);
    for (final g in FeatureGroup.all) {
      expect(find.byKey(ValueKey('featGroup_$g')), Features.inGroup(g).isEmpty ? findsNothing : findsOneWidget, reason: g);
    }
    for (final s in Features.registry) {
      expect(find.byKey(ValueKey('feat_${s.key}')), findsOneWidget, reason: s.key);
    }
  });
}
