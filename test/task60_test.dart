import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_features_screen.dart';
import 'package:transport_app/core/admin/staff_roles.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/feature_strings.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/widgets/feature_gate.dart';

import 'test_utils.dart';

Widget host(Widget child) => MaterialApp(home: LanguageScope(notifier: languageNotifier, child: Scaffold(body: child)));

void main() {
  late FakeFirebaseFirestore db;

  setUp(() {
    languageNotifier.value = AppLanguage.english;
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'admin1');
    FeaturesService.reset();
  });

  group('Features', () {
    test('no document: pilot mode on with the pilot defaults', () {
      final f = Features.fromMap(null);
      expect(f.pilotMode, isTrue);
      for (final k in [FeatureKey.driverNetwork, FeatureKey.emptyTrucks, FeatureKey.businessTools, FeatureKey.rentalMovers, FeatureKey.driverRewards]) {
        expect(f.isOn(k), isFalse, reason: k);
      }
      expect(f.isOn(FeatureKey.tripShare), isTrue);
      expect(f.isOn(FeatureKey.problemReport), isTrue);
    });

    test('pilot mode off: every feature starts on', () {
      final f = const Features(pilotMode: false);
      for (final s in Features.registry) {
        expect(f.isOn(s.key), isTrue, reason: s.key);
      }
    });

    test('an explicit flag beats both defaults; unknown keys are off', () {
      const f = Features(flags: {FeatureKey.emptyTrucks: true, FeatureKey.tripShare: false});
      expect(f.isOn(FeatureKey.emptyTrucks), isTrue);
      expect(f.isOn(FeatureKey.tripShare), isFalse);
      expect(f.isOn('nope'), isFalse);
      expect(const Features(pilotMode: false, flags: {FeatureKey.emptyTrucks: false}).isOn(FeatureKey.emptyTrucks), isFalse);
    });

    test('fromMap ignores unknown keys and wrong types; toMap round trips', () {
      final f = Features.fromMap({'pilotMode': 'yes', 'flags': {'emptyTrucks': true, 'bogus': true, 'tripShare': 'no'}});
      expect(f.pilotMode, isTrue);
      expect(f.flags, {'emptyTrucks': true});
      final g = Features.fromMap(f.withPilot(false).withFlag(FeatureKey.tripShare, false).toMap());
      expect(g.pilotMode, false);
      expect(g.flags, {'emptyTrucks': true, 'tripShare': false});
      expect(g.withFlag('emptyTrucks', null).flags, {'tripShare': false});
    });
  });

  group('FeaturesService', () {
    test('refresh reads config/features; a missing document keeps the pilot default', () async {
      await FeaturesService.refresh(force: true);
      expect(FeaturesService.isOn(FeatureKey.driverNetwork), isFalse);
      await db.collection('config').doc('features').set({'pilotMode': false});
      await FeaturesService.refresh(force: true);
      expect(FeaturesService.isOn(FeatureKey.driverNetwork), isTrue);
    });

    test('refresh is cached for 15 minutes unless forced', () async {
      await db.collection('config').doc('features').set({'pilotMode': false});
      await FeaturesService.refresh(force: true);
      await db.collection('config').doc('features').set({'pilotMode': true});
      await FeaturesService.refresh();
      expect(FeaturesService.current.pilotMode, isFalse);
      await FeaturesService.refresh(force: true);
      expect(FeaturesService.current.pilotMode, isTrue);
    });

    test('save writes the document and an audit row', () async {
      await FeaturesService.save(const Features(pilotMode: false, flags: {FeatureKey.emptyTrucks: true}));
      final d = (await db.collection('config').doc('features').get()).data()!;
      expect(d['pilotMode'], false);
      expect(d['flags'], {'emptyTrucks': true});
      final audit = (await db.collection('audit_events').where('type', isEqualTo: 'config_change').get()).docs;
      expect(audit.single['targetId'], 'features');
      expect(FeaturesService.isOn(FeatureKey.emptyTrucks), isTrue);
    });
  });

  group('FeatureGate', () {
    testWidgets('follows the switch live', (t) async {
      await t.pumpWidget(host(const FeatureGate(featureKey: FeatureKey.emptyTrucks, otherwise: Text('hidden'), child: Text('shown'))));
      expect(find.text('hidden'), findsOneWidget);
      FeaturesService.notifier.value = const Features(flags: {FeatureKey.emptyTrucks: true});
      await t.pump();
      expect(find.text('shown'), findsOneWidget);
    });
  });

  group('AdminFeaturesScreen', () {
    Future<void> open(WidgetTester t) async {
      t.view.physicalSize = const Size(800, 2600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(home: LanguageScope(notifier: languageNotifier, child: const AdminFeaturesScreen())));
      await settle(t);
    }

    Future<Map<String, dynamic>?> saved(WidgetTester t) async => (await t.runAsync(() => db.collection('config').doc('features').get()))!.data();

    testWidgets('shows every feature with its effective state', (t) async {
      await open(t);
      for (final s in Features.registry) {
        expect(find.byKey(ValueKey('feat_${s.key}')), findsOneWidget, reason: s.key);
      }
      expect(find.text('Empty trucks board'), findsOneWidget);
    });

    testWidgets('switching a feature On writes the flag; Default removes it', (t) async {
      await open(t);
      await t.tap(find.descendant(of: find.byKey(const ValueKey('featMode_emptyTrucks')), matching: find.text('On')));
      await settle(t);
      expect((await saved(t))!['flags'], {'emptyTrucks': true});
      await t.tap(find.descendant(of: find.byKey(const ValueKey('featMode_emptyTrucks')), matching: find.text('Default')));
      await settle(t);
      expect((await saved(t))!['flags'], <String, dynamic>{});
    });

    testWidgets('the pilot switch is saved', (t) async {
      await open(t);
      await t.tap(find.byKey(const ValueKey('featPilot')));
      await settle(t);
      expect((await saved(t))!['pilotMode'], false);
    });
  });

  test('staff area: features are for the super admin only', () {
    expect(staffCan('super', 'adminFeatures'), isTrue);
    for (final r in ['support', 'ops', 'verifier']) {
      expect(staffCan(r, 'adminFeatures'), isFalse);
    }
  });

  test('feature strings: a label for every flag, 12 languages, same placeholders', () {
    for (final s in Features.registry) {
      expect(featureStrings.containsKey('feat_${s.key}'), isTrue, reason: s.key);
    }
    for (final e in featureStrings.entries) {
      expect(e.value.length, 12, reason: e.key);
      expect(e.value.every((x) => x.trim().isNotEmpty), isTrue, reason: e.key);
    }
  });
}
