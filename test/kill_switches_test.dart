import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_features_screen.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/features/kill_switches.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';

import 'test_utils.dart';

/// Part 5 (H31): the emergency switches, and the incident plan that names them.
void main() {
  late FakeFirebaseFirestore db;

  setUp(() {
    languageNotifier.value = AppLanguage.english;
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'admin1');
    FeaturesService.reset();
  });

  group('the groups', () {
    test('every key in every group is a real feature', () {
      final keys = Features.registry.map((s) => s.key).toSet();
      for (final g in KillSwitches.groups) {
        expect(g.flags, isNotEmpty);
        for (final k in g.flags) {
          expect(keys.contains(k), isTrue, reason: '${g.id}: $k is not in Features.registry');
        }
      }
    });

    test('a group only ever writes OFF, and leaves the other switches alone', () {
      const before = Features(flags: {FeatureKey.emptyTrucks: true, FeatureKey.smsGateway: true});
      final after = before.withGroupOff(KillSwitches.byId('costs')!);
      expect(after.explicit(FeatureKey.smsGateway), isFalse);
      expect(after.explicit(FeatureKey.maps), isFalse);
      expect(after.explicit(FeatureKey.emptyTrucks), isTrue, reason: 'unrelated switch changed');
      expect(after.pilotMode, before.pilotMode);
      for (final v in after.flags.values.where((v) => v == true)) {
        expect(v, isTrue); // the only true left is the one that was true before
      }
      expect(after.flags.entries.where((e) => e.value && e.key != FeatureKey.emptyTrucks), isEmpty);
    });

    test('the "server" group covers every flag the Cloud Functions read as a server switch', () {
      final fns = File('functions/src/common.js').readAsStringSync();
      final list = RegExp(r'FLAGS = Object\.freeze\(\[([\s\S]*?)\]\)').firstMatch(fns)!.group(1)!;
      final serverFlags = RegExp(r"'(server\w+|paymentGateway|pushNotifications|dispatchV2)'").allMatches(list).map((m) => m.group(1)!).toSet();
      final covered = KillSwitches.byId('server')!.flags.toSet();
      expect(serverFlags.difference(covered), isEmpty, reason: 'a server switch is missing from the "server" group');
    });

    test('docs/INCIDENT_RESPONSE.md names every group and its switches', () {
      final doc = File('docs/INCIDENT_RESPONSE.md').readAsStringSync();
      for (final g in KillSwitches.groups) {
        expect(doc.contains('killGroup_${g.id}') || doc.contains('`${g.id}`'), isTrue, reason: g.id);
        for (final k in g.flags) {
          expect(doc.contains(k), isTrue, reason: '$k is not named in INCIDENT_RESPONSE.md');
        }
      }
    });
  });

  group('the screen', () {
    Future<void> open(WidgetTester t) async {
      t.view.physicalSize = const Size(800, 9000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(home: LanguageScope(notifier: languageNotifier, child: const AdminFeaturesScreen())));
      await settle(t);
    }

    testWidgets('a button asks first; Cancel changes nothing', (t) async {
      await open(t);
      await t.tap(find.byKey(const ValueKey('kill_money')));
      await t.pumpAndSettle();
      expect(find.textContaining('Switch off'), findsWidgets);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      final doc = await t.runAsync(() => db.collection('config').doc('features').get());
      expect(doc!.exists, isFalse);
    });

    testWidgets('confirming writes OFF for the whole group in one save', (t) async {
      await open(t);
      await t.tap(find.byKey(const ValueKey('kill_costs')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('killConfirmYes')));
      await settle(t);
      final flags = (await t.runAsync(() => db.collection('config').doc('features').get()))!.data()!['flags'] as Map;
      for (final k in KillSwitches.byId('costs')!.flags) {
        expect(flags[k], false, reason: k);
      }
    });
  });
}
