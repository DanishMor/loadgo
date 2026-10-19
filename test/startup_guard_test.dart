import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/errors/startup_failed_app.dart';
import 'package:transport_app/core/l10n/l10n.dart';

/// Part 5 (H16): the app must still start when one non-essential step breaks, and must say so calmly when it cannot start at all.
void main() {
  setUp(StartupGuard.reset);
  tearDown(() => languageNotifier.value = AppLanguage.english);

  group('StartupGuard.step', () {
    test('returns the value when the step works', () async {
      expect(await StartupGuard.step('ok', () async => 7), 7);
      expect(StartupGuard.failed, isEmpty);
    });

    test('a step that throws gives null and is listed; the next step still runs', () async {
      expect(await StartupGuard.step<int>('bad', () async => throw StateError('boom 9876543210')), isNull);
      expect(await StartupGuard.step('next', () async => 'fine'), 'fine');
      expect(StartupGuard.failed, ['bad']);
    });

    test('a step that throws before its first await (a sync throw) is caught too', () async {
      Future<int> syncThrow() => throw ArgumentError('early');
      expect(await StartupGuard.step<int>('sync', syncThrow), isNull);
      expect(StartupGuard.failed, ['sync']);
    });

    test('a step that never finishes is given up after the timeout', () async {
      final r = await StartupGuard.step<int>('hang', () => Future<int>.delayed(const Duration(seconds: 5), () => 1), timeout: const Duration(milliseconds: 50));
      expect(r, isNull);
      expect(StartupGuard.failed, ['hang']);
    });
  });

  group('main.dart', () {
    final main = File('lib/main.dart').readAsStringSync();

    test('Firebase failing to start shows the fallback app with a retry, and does not go on', () {
      final init = main.indexOf('await Firebase.initializeApp');
      final fallback = main.indexOf('runApp(StartupFailedApp(onRetry: main))');
      final real = main.indexOf('runApp(const LoadGoApp())');
      expect(init, greaterThan(0));
      expect(fallback, greaterThan(init));
      expect(real, greaterThan(fallback));
      expect(main.substring(fallback, fallback + 80).contains('return;'), isTrue);
    });

    test('every step after Firebase that is not essential is guarded', () {
      for (final step in ['CrashService.init', 'AppCheckSetup.start', 'PushRouter.start', 'Backend.enableOfflinePersistence', 'LanguageStore.loadLocal', 'ConnectivityService.start', 'ThemeStore.load']) {
        final at = main.indexOf(step);
        expect(at, greaterThan(0), reason: step);
        expect(main.substring(at - 80, at).contains('StartupGuard.step'), isTrue, reason: '$step is not inside StartupGuard.step');
      }
    });

    test('the picture cache is capped for low-memory phones', () {
      expect(RegExp(r'imageCache\s*\.\.maximumSizeBytes = 48 << 20').hasMatch(main), isTrue);
    });

    test('uncaught async errors and framework errors are both caught and cleaned', () {
      expect(main.contains('PlatformDispatcher.instance.onError'), isTrue);
      expect(File('lib/core/services/crash_service.dart').readAsStringSync().contains('FlutterError.onError'), isTrue);
      expect(main.contains('ErrorWidget.builder'), isTrue);
    });
  });

  group('StartupFailedApp', () {
    Future<void> show(WidgetTester tester, {double scale = 1, AppLanguage lang = AppLanguage.english, Size size = const Size(360, 640), VoidCallback? onRetry}) async {
      languageNotifier.value = lang;
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MediaQuery(data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)), child: StartupFailedApp(onRetry: onRetry ?? () {})));
      await tester.pump();
    }

    testWidgets('one sentence and one button; the button calls retry', (tester) async {
      var tries = 0;
      await show(tester, onRetry: () => tries++);
      expect(find.text('The app could not start'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('startRetry')));
      expect(tries, 1);
    });

    for (final lang in AppLanguage.values) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('${lang.name} at text scale $scale does not overflow at 360x640', (tester) async {
          await show(tester, lang: lang, scale: scale);
          expect(tester.takeException(), isNull);
          expect(find.byKey(const ValueKey('startRetry')), findsOneWidget);
        });
      }
    }
  });
}
