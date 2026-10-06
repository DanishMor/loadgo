import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/app_control/app_control.dart';
import 'package:transport_app/core/app_info.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/l10n/app_control_strings.dart';
import 'package:transport_app/core/services/analytics_events.dart';
import 'package:transport_app/core/services/app_control_service.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/crash_service.dart';
import 'package:transport_app/core/widgets/app_control_gate.dart';

void main() {
  setUp(() {
    languageNotifier.value = AppLanguage.english;
    AppControlService.reset();
  });

  group('VersionGate', () {
    test('codeOf reads the build number', () {
      expect(VersionGate.codeOf('1.0.0+7'), 7);
      expect(VersionGate.codeOf('1.0.0'), 0);
      expect(VersionGate.codeOf('1.0.0+x'), 0);
      expect(VersionGate.codeOf(appVersion), greaterThan(0));
    });

    test('blocks only when the minimum is positive and above the current build', () {
      expect(VersionGate.needsUpdate(3, 0), isFalse);
      expect(VersionGate.needsUpdate(3, 3), isFalse);
      expect(VersionGate.needsUpdate(3, 4), isTrue);
      expect(VersionGate.needsUpdate(0, 1), isTrue);
    });
  });

  group('AppControl parsing', () {
    test('missing or odd data never blocks', () {
      expect(AppControl.fromMap(null), AppControl.open);
      final c = AppControl.fromMap({'minVersionCode': -4, 'maintenance': 'yes', 'maintenanceMessage': 5, 'flags': 'nope'});
      expect(c.minVersionCode, 0);
      expect(c.maintenance, isFalse);
      expect(c.maintenanceMessage, '');
      expect(c.flags, isEmpty);
    });

    test('reads values, string numbers, JSON flags and caps the message', () {
      final c = AppControl.fromMap({
        'minVersionCode': '12',
        'maintenance': true,
        'maintenanceMessage': 'x' * 400,
        'flags': '{"surge": true, "bad": 1, "off": false}',
      });
      expect(c.minVersionCode, 12);
      expect(c.maintenance, isTrue);
      expect(c.maintenanceMessage.length, 300);
      expect(c.flags, {'surge': true, 'off': false});
    });

    test('remote values override the Firestore fallback only where they are set', () {
      const fallback = AppControl(minVersionCode: 9, maintenance: true, maintenanceMessage: 'fs', flags: {'a': true, 'b': false});
      const remote = AppControl(minVersionCode: 0, maintenance: false, flags: {'b': true});
      final merged = remote.overlay(fallback, hasMin: false, hasMaintenance: true, hasMessage: false);
      expect(merged.minVersionCode, 9);
      expect(merged.maintenance, isFalse);
      expect(merged.maintenanceMessage, 'fs');
      expect(merged.flags, {'a': true, 'b': true});
    });
  });

  group('FeatureFlags', () {
    test('unknown flags are off unless a default is given', () {
      FeatureFlags.set(const {'surge': true, 'chat': false});
      expect(FeatureFlags.isOn('surge'), isTrue);
      expect(FeatureFlags.isOn('chat', defaultValue: true), isFalse);
      expect(FeatureFlags.isOn('missing'), isFalse);
      expect(FeatureFlags.isOn('missing', defaultValue: true), isTrue);
    });
  });

  group('service', () {
    test('refresh falls back to config/app and sets the flags', () async {
      final db = FakeFirebaseFirestore();
      Backend.useFakes(db: db, uid: () => 'u1');
      await db.collection('config').doc('app').set({'minVersionCode': 4, 'flags': {'surge': true}});
      await AppControlService.refresh();
      expect(AppControlService.notifier.value.minVersionCode, 4);
      expect(FeatureFlags.isOn('surge'), isTrue);
    });

    test('refresh with no document leaves the app open', () async {
      Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'u1');
      await AppControlService.refresh();
      expect(AppControlService.notifier.value, AppControl.open);
    });

    test('Remote Config defaults are documented keys', () {
      expect(AppControlService.remoteDefaults.keys, containsAll(['min_version_code', 'maintenance', 'maintenance_message', 'feature_flags']));
      expect(AppControlService.fetchInterval, const Duration(hours: 1));
    });
  });

  group('safe without Firebase', () {
    test('crash and analytics calls do nothing and do not throw', () async {
      CrashService.record(StateError('x'), StackTrace.current);
      expect(CrashService.active, isFalse);
      AnalyticsEvents.enabled = true;
      await AnalyticsEvents.log('load_posted');
      await AnalyticsEvents.screen('home');
      AnalyticsEvents.enabled = false;
    });

    test('analytics keeps only valid names and short coded params', () {
      expect(AnalyticsEvents.validName('load_posted'), isTrue);
      expect(AnalyticsEvents.validName('Load Posted'), isFalse);
      expect(AnalyticsEvents.validName('1abc'), isFalse);
      final p = AnalyticsEvents.cleanParams({'screen_name': 'home', 'n': 3, 'bad key': 'x', 'obj': Object(), 'long': 'y' * 50});
      expect(p.keys, unorderedEquals(['screen_name', 'n', 'long']));
      expect((p['long']! as String).length, 36);
    });
  });

  group('screens', () {
    Widget app(Widget child) => MaterialApp(home: LanguageScope(notifier: languageNotifier, child: child));

    testWidgets('open app shows the child', (t) async {
      await t.pumpWidget(app(const AppControlGate(currentCode: 1, child: Text('home'))));
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('an old build sees the update screen', (t) async {
      AppControlService.apply(const AppControl(minVersionCode: 5));
      await t.pumpWidget(app(const AppControlGate(currentCode: 2, child: Text('home'))));
      expect(find.text('home'), findsNothing);
      expect(find.text('Update needed'), findsOneWidget);
      expect(find.text('Update now'), findsOneWidget);
    });

    testWidgets('maintenance shows the message, or a default', (t) async {
      AppControlService.apply(const AppControl(maintenance: true, maintenanceMessage: 'Back at 6 pm'));
      await t.pumpWidget(app(const AppControlGate(currentCode: 9, child: Text('home'))));
      expect(find.text('Back at 6 pm'), findsOneWidget);
      AppControlService.apply(const AppControl(maintenance: true));
      await t.pumpAndSettle();
      expect(find.text('Under maintenance'), findsOneWidget);
      expect(find.text('LoadGo is being improved. Please try again in a little while.'), findsOneWidget);
    });

    testWidgets('clears when the admin lifts maintenance', (t) async {
      AppControlService.apply(const AppControl(maintenance: true));
      await t.pumpWidget(app(const AppControlGate(currentCode: 9, child: Text('home'))));
      AppControlService.apply(AppControl.open);
      await t.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
    });
  });

  test('strings have 12 languages', () {
    for (final e in appControlStrings.entries) {
      expect(e.value.length, 12, reason: e.key);
      expect(e.value.every((s) => s.isNotEmpty), isTrue, reason: e.key);
    }
  });
}
