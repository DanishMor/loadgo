import 'package:transport_app/core/app_info.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/l10n/permission_strings.dart';
import 'package:transport_app/core/permissions/permission_rationale.dart';
import 'package:transport_app/core/settings/legal_screens.dart';
import 'package:transport_app/core/settings/policy_links.dart';

Widget host(Widget child) => MaterialApp(home: LanguageScope(notifier: languageNotifier, child: child));

void main() {
  setUp(() {
    languageNotifier.value = AppLanguage.english;
    SharedPreferences.setMockInitialValues({});
    PolicyLinks.setBase(null);
  });

  group('PolicyLinks', () {
    test('default pages', () {
      expect(PolicyLinks.privacy(), 'https://loadgo-defc2.web.app/privacy');
      expect(PolicyLinks.terms(), 'https://loadgo-defc2.web.app/terms');
      expect(PolicyLinks.deleteAccount(), 'https://loadgo-defc2.web.app/delete-account');
    });

    test('clean accepts a plain https URL and drops trailing slashes', () {
      expect(PolicyLinks.clean(' https://loadgo.in/ '), 'https://loadgo.in');
      expect(PolicyLinks.clean('https://a.b/c//'), 'https://a.b/c');
    });

    test('clean refuses http, other schemes, spaces, queries, long or non-text values', () {
      for (final bad in ['http://loadgo.in', 'javascript:alert(1)', 'https://a b.in', 'https://a.in?x=1', 'https://a.in#f', 'https://', '', '   ', 'loadgo.in', 'https://${'a' * 200}.in', 5, null]) {
        expect(PolicyLinks.clean(bad), isNull, reason: '$bad');
      }
    });

    test('setBase switches and falls back to the default', () {
      PolicyLinks.setBase('https://loadgo.in');
      expect(PolicyLinks.privacy(), 'https://loadgo.in/privacy');
      PolicyLinks.setBase('ftp://x');
      expect(PolicyLinks.privacy(), 'https://loadgo-defc2.web.app/privacy');
      expect(PolicyLinks.terms('https://other.in'), 'https://other.in/terms');
    });
  });

  group('PermissionRationale', () {
    Future<void> open(WidgetTester t, RationaleKind k, void Function(bool) got) async {
      await t.pumpWidget(host(Builder(builder: (c) => TextButton(onPressed: () async => got(await PermissionRationale.ask(c, k)), child: const Text('go')))));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
    }

    testWidgets('first time: explains, Continue returns true and is remembered', (t) async {
      bool? got;
      await open(t, RationaleKind.microphone, (v) => got = v);
      expect(find.text('Use the microphone?'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('rationaleYes')));
      await t.pumpAndSettle();
      expect(got, isTrue);
      expect(await PermissionRationale.seen(RationaleKind.microphone), isTrue);
      expect(await PermissionRationale.seen(RationaleKind.location), isFalse, reason: 'per permission');
      got = null;
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(find.text('Use the microphone?'), findsNothing, reason: 'asked only once');
      expect(got, isTrue);
    });

    testWidgets('Not now returns false and asks again next time', (t) async {
      bool? got;
      await open(t, RationaleKind.location, (v) => got = v);
      expect(find.text('Use your location?'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('rationaleNo')));
      await t.pumpAndSettle();
      expect(got, isFalse);
      expect(await PermissionRationale.seen(RationaleKind.location), isFalse);
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(find.text('Use your location?'), findsOneWidget);
    });

    testWidgets('every kind has text in all languages', (t) async {
      for (final k in RationaleKind.values) {
        final (title, body, _) = PermissionRationale.textFor(k);
        expect(permissionStrings[title]?.length, 12);
        expect(permissionStrings[body]?.length, 12);
      }
    });
  });

  group('PolicyScreen', () {
    testWidgets('privacy and terms show the public page link; refund does not', (t) async {
      await t.pumpWidget(host(PolicyScreen.privacy));
      expect(find.byKey(const ValueKey('policyWebLink')), findsOneWidget);
      expect(find.text('https://loadgo-defc2.web.app/privacy'), findsOneWidget);
      await t.pumpWidget(host(PolicyScreen.terms));
      expect(find.text('https://loadgo-defc2.web.app/terms'), findsOneWidget);
      await t.pumpWidget(host(PolicyScreen.refund));
      expect(find.byKey(const ValueKey('policyWebLink')), findsNothing);
    });

    testWidgets('a changed base shows in the link', (t) async {
      PolicyLinks.setBase('https://loadgo.in');
      await t.pumpWidget(host(PolicyScreen.privacy));
      expect(find.text('https://loadgo.in/privacy'), findsOneWidget);
    });
  });

  group('Play Store pack files', () {
    test('manifest label is the app name and declares exactly the documented permissions', () {
      final m = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(m, contains('android:label="${AppInfo.name}"'));
      final perms = RegExp(r'uses-permission android:name="android\.permission\.(\w+)"').allMatches(m).map((x) => x[1]).toSet();
      expect(perms, {'ACCESS_FINE_LOCATION', 'ACCESS_COARSE_LOCATION', 'POST_NOTIFICATIONS', 'RECORD_AUDIO', 'INTERNET', 'MODIFY_AUDIO_SETTINGS', 'ACCESS_NETWORK_STATE', 'CHANGE_NETWORK_STATE'});
      final checklist = File('docs/PLAY_STORE_CHECKLIST.md').readAsStringSync();
      for (final p in perms) {
        expect(checklist, contains(p!.split('_').first == 'ACCESS' ? 'ACCESS_FINE_LOCATION' : p));
      }
    });

    test('hosting folder has the policy pages and firebase.json serves them', () {
      for (final f in ['index', 'privacy', 'terms', 'delete-account']) {
        final html = File('hosting/$f.html').readAsStringSync();
        expect(html, startsWith('<!doctype html>'));
        expect(html, contains('name="viewport"'));
      }
      final h = jsonDecode(File('firebase.json').readAsStringSync())['hosting'] as Map;
      expect(h['public'], 'hosting');
      final sources = [for (final r in h['rewrites'] as List) (r as Map)['source']];
      expect(sources, containsAll(['/privacy', '/terms', '/delete-account']));
      expect(File('hosting/privacy.html').readAsStringSync(), contains('Microphone'));
    });

    test('docs exist', () {
      for (final f in ['PLAY_STORE_CHECKLIST', 'PRIVACY_POLICY', 'TERMS', 'PAID_UPGRADE_PLAN']) {
        expect(File('docs/$f.md').readAsStringSync().length, greaterThan(500), reason: f);
      }
    });
  });

  test('permission strings: 12 non-empty languages, same placeholders', () {
    final ph = RegExp(r'\{(\w+)\}');
    for (final e in permissionStrings.entries) {
      expect(e.value.length, 12, reason: e.key);
      expect(e.value.every((s) => s.trim().isNotEmpty), isTrue, reason: e.key);
      final want = ph.allMatches(e.value[0]).map((m) => m[1]).toSet();
      for (var i = 1; i < 12; i++) {
        expect(ph.allMatches(e.value[i]).map((m) => m[1]).toSet(), want, reason: '${e.key}/$i');
      }
    }
  });
}
