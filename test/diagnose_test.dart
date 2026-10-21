import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/diagnose/diagnose.dart';
import 'package:transport_app/core/diagnose/diagnose_screen.dart';
import 'package:transport_app/core/errors/friendly_error.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/connectivity_service.dart';
import 'package:transport_app/core/widgets/live_stream.dart';

import 'test_utils.dart';

/// Z1 and Z3: the Diagnose screen, the reason codes and the masked report.
void main() {
  FirebaseException fe(String code, [String? message]) => FirebaseException(plugin: 'cloud_firestore', code: code, message: message);
  const link = 'https://console.firebase.google.com/v1/r/project/p1/firestore/indexes?create_composite=abc';

  setUp(() {
    languageNotifier.value = AppLanguage.english;
    ConnectivityService.online.value = true;
  });

  test('errors are sorted into OK, no access, needs index, offline and timeout', () {
    expect(Diagnose.classify(fe('permission-denied')), ProbeStatus.noAccess);
    expect(Diagnose.classify(fe('failed-precondition', 'The query requires an index. You can create it here: $link')), ProbeStatus.needsIndex);
    expect(Diagnose.classify(fe('failed-precondition', 'something else')), ProbeStatus.other);
    expect(Diagnose.classify(fe('unavailable')), ProbeStatus.offline);
    expect(Diagnose.classify(TimeoutException('x')), ProbeStatus.timeout);
    expect(Diagnose.classify(TimeoutException('x'), online: false), ProbeStatus.offline);
    expect(Diagnose.classify(StateError('boom')), ProbeStatus.other);
    expect([for (final s in ProbeStatus.values) s.code], [null, 'E-PERM', 'E-INDEX', 'E-NET', 'E-TIMEOUT', 'E-GEN']);
  });

  test('friendly error knows an index problem; the code follows the message key', () {
    expect(FriendlyError.of(fe('failed-precondition', 'The query requires an index.')), 'errorIndex');
    expect(FriendlyError.of(fe('failed-precondition', 'already changed')), FriendlyError.conflict);
    expect([for (final k in ['errorNoAccess', 'errorIndex', 'errorNetwork', 'errorOffline', 'errorSlow', 'errorGeneric']) Diagnose.codeForKey(k)], ['E-PERM', 'E-INDEX', 'E-NET', 'E-NET', 'E-TIMEOUT', 'E-GEN']);
  });

  test('a probe keeps the console link of an index error and a 6 second limit stops a stuck read', () async {
    final r = await Diagnose.probe('x', () => Future.error(fe('failed-precondition', 'The query requires an index for fields a, b. $link')));
    expect(r.status, ProbeStatus.needsIndex);
    expect(r.consoleLink, link);
    final slow = await Diagnose.probe('y', () => Completer<Object?>().future, timeout: const Duration(milliseconds: 20));
    expect(slow.status, ProbeStatus.timeout);
    expect((await Diagnose.probe('z', () async => 1)).status, ProbeStatus.ok);
  });

  test('the report lists every flag, masks phone numbers and tokens, and has no secrets', () async {
    final results = [
      const ProbeResult('LR register +91 99999 00001', ProbeStatus.noAccess, ms: 12),
      const ProbeResult('loads', ProbeStatus.needsIndex, detail: 'index for user AIzaSyA1234567890123456789012345678901', consoleLink: link),
    ];
    final text = Diagnose.report(results: results, features: Features.pilotDefault, online: true, platform: 'android', role: 'driver');
    expect(text, contains('E-PERM'));
    expect(text, contains('E-INDEX'));
    expect(text, contains(link));
    expect(text, contains('uiV2'));
    expect(text, isNot(contains('99999')));
    expect(text, isNot(contains('AIza')));
  });

  testWidgets('the screen runs the checks, shows one row per query with its code, and copies the report', (tester) async {
    tester.view.physicalSize = const Size(360 * 2, 640 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    String? copied;
    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(
        home: DiagnoseScreen(
          role: 'driver',
          timeout: const Duration(milliseconds: 50),
          copy: (t) async => copied = t,
          probes: [
            ('good', () async => 1),
            ('denied', () => Future.error(fe('permission-denied'))),
            ('stuck', () => Completer<Object?>().future),
          ],
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('dgRun')));
    await tester.pump(const Duration(milliseconds: 200));
    await settle(tester);
    expect(find.byKey(const ValueKey('dgRow_good')), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
    expect(find.text('E-PERM'), findsOneWidget);
    expect(find.text('E-TIMEOUT'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('dgCopy')));
    await tester.tap(find.byKey(const ValueKey('dgCopy')));
    await tester.pump();
    expect(copied, contains('denied: E-PERM'));
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('an error screen shows the reason code and a Diagnose button (dark: $dark, 2.0x text, Hindi)', (tester) async {
      languageNotifier.value = AppLanguage.hindi;
      tester.view.physicalSize = const Size(360 * 2, 640 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(LanguageScope(
        notifier: languageNotifier,
        child: MaterialApp(
          theme: dark ? ThemeData.dark() : ThemeData.light(),
          builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(2)), child: w!),
          home: Scaffold(body: ErrorState(error: fe('permission-denied'), onRetry: () {})),
        ),
      ));
      await settle(tester);
      expect(find.byKey(const ValueKey('diagnoseBtn')), findsOneWidget);
      expect(find.textContaining('E-PERM'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the slow screen says E-TIMEOUT and offers Diagnose', (tester) async {
    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(home: Scaffold(body: LiveStream<int>(stream: () => const Stream<int>.empty(), slowAfter: const Duration(milliseconds: 10), builder: (c, d) => Text('$d')))),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('This is taking longer than usual.'), findsOneWidget);
    expect(find.textContaining('E-TIMEOUT'), findsOneWidget);
  });
}
