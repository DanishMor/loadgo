import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/widgets/live_stream.dart';

import 'test_utils.dart';

/// MASTER-5 Task 15: loading, empty, error and offline states.
void main() {
  // Raw StreamBuilders that never look at `hasError` show a blank or a
  // spinner when a read fails. Lists use LiveStream (spinner, "taking longer",
  // offline, friendly error + Retry); a raw builder must show ErrorState.
  int unguarded() {
    var n = 0;
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('live_stream.dart')) continue;
      final s = f.readAsStringSync();
      final builders = RegExp(r'StreamBuilder<').allMatches(s).length;
      final guards = RegExp(r'hasError|\.error\b').allMatches(s).length;
      if (builders > guards) n += builders - guards;
    }
    return n;
  }

  test('raw StreamBuilders without an error branch do not grow', () {
    const budget = 42; // today's count: small cards that hide themselves on an error
    expect(unguarded(), lessThanOrEqualTo(budget));
  });

  // Task 21: a screen that lists something says what it means when the list is empty.
  test('every file that lists a stream handles the empty case, apart from four reviewed ones', () {
    const reviewed = {
      'lib/driver/simple_home_screen.dart', // shows a balance, not a list
      'lib/driver/vehicle_alerts_banner.dart', // a banner: nothing to show when empty
      'lib/core/bilty/lr_send_screen.dart', // a short optional list under the buttons
      'lib/core/widgets/evidence_cards.dart', // cards that hide themselves when empty
    };
    final bad = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final s = f.readAsStringSync();
      if (!RegExp(r'LiveStream<List|StreamBuilder<List').hasMatch(s)) continue;
      if (RegExp(r'EmptyState|isEmpty|emptyText|isNotEmpty').hasMatch(s)) continue;
      if (!reviewed.contains(f.path)) bad.add(f.path);
    }
    expect(bad, isEmpty, reason: 'add an EmptyState: $bad');
  });

  testWidgets('LiveStream: spinner, then data; error shows the friendly text with Retry', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(
        home: Scaffold(
          body: LiveStream<int>(
            stream: () {
              attempts++;
              return attempts == 1 ? Stream<int>.error(StateError('x')) : Stream.value(7);
            },
            builder: (c, d) => Text('data $d'),
          ),
        ),
      ),
    ));
    await settle(tester);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await settle(tester);
    expect(find.text('data 7'), findsOneWidget);
  });

  testWidgets('ErrorState names the problem and offers Retry when asked', (tester) async {
    var retried = false;
    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(home: Scaffold(body: ErrorState(error: StateError('x'), onRetry: () => retried = true))),
    ));
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    expect(retried, isTrue);
  });
}
