import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/navigation/app_routes.dart';
import 'package:transport_app/core/navigation/deep_links.dart';
import 'package:transport_app/core/share/share_links.dart';

void main() {
  setUp(() {
    DeepLinks.reset();
    ShareLinks.host = 'loadgo-defc2.web.app';
  });

  group('DeepLinks parsing', () {
    test('a full link and a route name give the load id', () {
      expect(DeepLinks.loadIdFrom('https://loadgo-defc2.web.app/load/abc123'), 'abc123');
      expect(DeepLinks.loadIdFrom('/load/abc123'), 'abc123');
      expect(DeepLinks.loadIdFrom('  /load/a%20b  '), 'a b');
    });

    test('anything else is ignored', () {
      for (final bad in [null, '', '/', '/privacy', '/load', '/load/', '/load/a/b', 'ftp://x/load/a', 'load/abc', 'https://x.in/other/abc', '/load/${'a' * 65}']) {
        expect(DeepLinks.loadIdFrom(bad), isNull, reason: '$bad');
      }
    });

    test('handle remembers only load links', () {
      expect(DeepLinks.handle('/privacy'), isFalse);
      expect(DeepLinks.pendingLoadId.value, isNull);
      expect(DeepLinks.handle('/load/L9'), isTrue);
      expect(DeepLinks.pendingLoadId.value, 'L9');
    });

    testWidgets('a link that arrives while the app runs is taken by the observer', (t) async {
      DeepLinks.start();
      final msg = const JSONMethodCodec().encodeMethodCall(MethodCall('pushRouteInformation', <String, dynamic>{'location': 'https://loadgo-defc2.web.app/load/NEW1'}));
      await t.binding.defaultBinaryMessenger.handlePlatformMessage('flutter/navigation', msg, (_) {});
      await t.pump();
      expect(DeepLinks.pendingLoadId.value, 'NEW1');
    });

    testWidgets('other routes are left to the navigator', (t) async {
      DeepLinks.start();
      expect(await DeepLinks.observerForTest.didPushRouteInformation(RouteInformation(uri: Uri.parse('/privacy'))), isFalse);
      expect(await DeepLinks.observerForTest.didPushRouteInformation(RouteInformation(uri: Uri.parse('/load/Z'))), isTrue);
      expect(DeepLinks.pendingLoadId.value, 'Z');
    });
  });

  group('DeepLinkListener', () {
    final opened = <String>[];
    void Function(BuildContext, String, {required bool isDriver})? before;

    setUp(() {
      opened.clear();
      before = AppRoutes.openLoad;
      AppRoutes.openLoad = (context, id, {required isDriver}) => opened.add('$id/${isDriver ? 'driver' : 'customer'}');
    });
    tearDown(() => AppRoutes.openLoad = before);

    testWidgets('a link waiting before the home appears is opened once, then cleared', (t) async {
      DeepLinks.handle('/load/L1');
      await t.pumpWidget(const MaterialApp(home: DeepLinkListener(isDriver: true, child: Text('home'))));
      await t.pump();
      expect(opened, ['L1/driver']);
      expect(DeepLinks.pendingLoadId.value, isNull);
      await t.pump();
      expect(opened.length, 1);
    });

    testWidgets('a link that arrives later is opened for the customer', (t) async {
      await t.pumpWidget(const MaterialApp(home: DeepLinkListener(isDriver: false, child: Text('home'))));
      await t.pump();
      expect(opened, isEmpty);
      DeepLinks.handle('https://loadgo-defc2.web.app/load/L2');
      await t.pump();
      expect(opened, ['L2/customer']);
    });

    testWidgets('after the screen is gone nothing is opened', (t) async {
      await t.pumpWidget(const MaterialApp(home: DeepLinkListener(isDriver: true, child: Text('home'))));
      await t.pumpWidget(const MaterialApp(home: Text('other')));
      DeepLinks.handle('/load/L3');
      await t.pump();
      expect(opened, isEmpty);
      expect(DeepLinks.pendingLoadId.value, 'L3', reason: 'kept for the next home');
    });
  });

  group('project files', () {
    test('manifest opens load links for the share host', () {
      final m = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(m, contains('android:host="${ShareLinks.host}"'));
      expect(m, contains('android:pathPrefix="/load/"'));
      expect(m, contains('android.intent.category.BROWSABLE'));
    });

    test('hosting serves a fallback page for /load/**', () {
      final h = jsonDecode(File('firebase.json').readAsStringSync())['hosting'] as Map;
      expect([for (final r in h['rewrites'] as List) (r as Map)['source']], contains('/load/**'));
      final page = File('hosting/load.html').readAsStringSync();
      expect(page, startsWith('<!doctype html>'));
      expect(page, contains('name="viewport"'));
    });

    test('the assetlinks template is valid JSON with placeholders to fill', () {
      final j = jsonDecode(File('docs/assetlinks.template.json').readAsStringSync()) as List;
      expect((j.single as Map)['target']['namespace'], 'android_app');
      expect(File('hosting/.well-known/assetlinks.json').existsSync(), isFalse, reason: 'must not be served with placeholder values');
    });
  });
}
