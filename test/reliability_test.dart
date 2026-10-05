import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/connectivity_service.dart';
import 'package:transport_app/core/widgets/common.dart';
import 'package:transport_app/core/widgets/live_stream.dart';

import 'test_utils.dart';

void main() {
  setUp(() {
    languageNotifier.value = AppLanguage.english;
    ConnectivityService.online.value = true;
  });
  tearDown(() => ConnectivityService.online.value = true);

  test('Firestore keeps an offline cache of 100 MB', () {
    expect(Backend.firestoreSettings.persistenceEnabled, isTrue);
    expect(Backend.firestoreSettings.cacheSizeBytes, 100 * 1024 * 1024);
  });

  test('no screen waits forever on a document that does not exist', () {
    // The old pattern was "if (x == null) return const Center(child: CircularProgressIndicator())"
    // on a stream that can legitimately emit null. LiveDoc shows "not found" instead.
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (RegExp(r'if \((?:b|t|c|snap\.data) == null\) return const Center\(child: CircularProgressIndicator\(\)\)').hasMatch(lines[i])) {
          offenders.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  testWidgets('LiveDoc: spinner, then data, null as "missing", error with Retry that resubscribes', (tester) async {
    final controller = StreamController<String?>();
    addTearDown(controller.close);
    var subscriptions = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LiveDoc<String>(
          stream: () {
            subscriptions++;
            return subscriptions == 1 ? Stream<String?>.error('boom') : controller.stream;
          },
          builder: (context, v) => Text(v == null ? 'missing' : 'got $v'),
        ),
      ),
    ));
    await settle(tester);
    expect(find.text('Retry'), findsOneWidget, reason: 'the first subscription failed');
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(subscriptions, 2);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    controller.add(null);
    await tester.pump();
    expect(find.text('missing'), findsOneWidget);
    controller.add('x');
    await tester.pump();
    expect(find.text('got x'), findsOneWidget);
  });

  testWidgets('offline with nothing loaded says so, with Retry; the banner follows connectivity', (tester) async {
    ConnectivityService.online.value = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          const OfflineBanner(),
          Expanded(child: LiveStream<int>(stream: () => const Stream<int>.empty(), builder: (c, v) => Text('$v'))),
        ]),
      ),
    ));
    await tester.pump();
    expect(find.text('No internet connection. Connect and try again.'), findsOneWidget);
    expect(find.text('You\'re offline. Showing saved data.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    ConnectivityService.online.value = true;
    await tester.pump();
    expect(find.byType(OfflineBanner), findsOneWidget);
    expect(find.byIcon(Icons.wifi_off_rounded), findsNothing);
  });

  testWidgets('showRetrySnack shows the message and calls back on Retry', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(onPressed: () => showRetrySnack(context, 'Something went wrong', () => calls++), child: const Text('go')),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600)); // the snack bar slides in
    expect(find.text('Something went wrong'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(calls, 1);
  });
}
