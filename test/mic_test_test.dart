import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/call/mic_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';

class _Probe implements MicProbe {
  final MicResult result;
  final StreamController<double> c = StreamController<double>.broadcast();
  bool closed = false;
  _Probe(this.result);
  @override
  Future<MicResult> open() async => result;
  @override
  Stream<double> get levels => c.stream;
  @override
  Future<void> close() async => closed = true;
}

/// MASTER-6 Task 35: Test my mic.
void main() {
  Future<void> show(WidgetTester t, _Probe p) async {
    await t.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: MicTestScreen(probe: () => p))));
    await t.pump();
  }

  test('a level of 0.25 or more counts as heard', () {
    expect(MicVerdict.heard([0.0, 0.1]), isFalse);
    expect(MicVerdict.heard([0.0, 0.3]), isTrue);
  });

  testWidgets('allowed: shows a level bar, then "we heard you"', (t) async {
    final p = _Probe(MicResult.ok);
    await show(t, p);
    await t.tap(find.byKey(const ValueKey('mtStart')));
    await t.pump();
    await t.pump();
    expect(find.byKey(const ValueKey('mtSpeak')), findsOneWidget);
    expect(find.byKey(const ValueKey('mtNoMeter')), findsOneWidget);
    p.c.add(0.1);
    await t.pump();
    expect(find.byKey(const ValueKey('mtLevel')), findsOneWidget);
    expect(find.byKey(const ValueKey('mtTips')), findsOneWidget);
    expect(find.byKey(const ValueKey('mtHeard')), findsNothing);
    p.c.add(0.6);
    await t.pump();
    expect(find.byKey(const ValueKey('mtHeard')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    expect(p.closed, isTrue);
  });

  testWidgets('denied and unavailable give plain steps and close the mic', (t) async {
    final d = _Probe(MicResult.denied);
    await show(t, d);
    await t.tap(find.byKey(const ValueKey('mtStart')));
    await t.pump();
    await t.pump();
    expect(find.byKey(const ValueKey('mtDenied')), findsOneWidget);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    expect(d.closed, isTrue);

    final u = _Probe(MicResult.unavailable);
    await show(t, u);
    await t.pumpWidget(const SizedBox());
    await show(t, u);
    await t.tap(find.byKey(const ValueKey('mtStart')));
    await t.pump();
    await t.pump();
    expect(find.byKey(const ValueKey('mtUnavailable')), findsOneWidget);
  });
}
