import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/flagged_users_screen.dart';
import 'package:transport_app/core/errors/friendly_error.dart';
import 'package:transport_app/core/l10n/friendly_error_strings.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/network/with_retry.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/connectivity_service.dart';
import 'package:transport_app/core/widgets/common.dart';
import 'package:transport_app/core/widgets/live_stream.dart';

import 'test_utils.dart';

Widget host(Widget child) => MaterialApp(home: LanguageScope(notifier: languageNotifier, child: Scaffold(body: child)));
FirebaseException fe(String code) => FirebaseException(plugin: 'firestore', code: code);

class SocketException implements Exception {}

void main() {
  setUp(() {
    languageNotifier.value = AppLanguage.english;
    ConnectivityService.online.value = true;
  });

  group('FriendlyError', () {
    test('Firebase codes map to messages', () {
      expect(FriendlyError.of(fe('permission-denied')), 'errorNoAccess');
      for (final c in ['unauthenticated', 'user-token-expired', 'requires-recent-login']) {
        expect(FriendlyError.of(fe(c)), 'errorSession', reason: c);
      }
      for (final c in ['unavailable', 'deadline-exceeded', 'network-request-failed']) {
        expect(FriendlyError.of(fe(c)), 'errorNetwork', reason: c);
      }
      expect(FriendlyError.of(fe('not-found')), 'errorNotFound');
      for (final c in ['resource-exhausted', 'aborted', 'too-many-requests']) {
        expect(FriendlyError.of(fe(c)), 'errorBusy', reason: c);
      }
      for (final c in ['already-exists', 'failed-precondition']) {
        expect(FriendlyError.of(fe(c)), 'errorConflict', reason: c);
      }
      expect(FriendlyError.of(fe('internal')), 'errorGeneric');
    });

    test('timeouts and socket errors are network; anything else is generic', () {
      expect(FriendlyError.of(TimeoutException('x')), 'errorNetwork');
      expect(FriendlyError.of(SocketException()), 'errorNetwork');
      expect(FriendlyError.of(StateError('boom')), 'errorGeneric');
      expect(FriendlyError.of(null), 'errorGeneric');
      expect(FriendlyError.of('text'), 'errorGeneric');
    });

    test('only network and busy failures are transient', () {
      expect(FriendlyError.isTransient(fe('unavailable')), isTrue);
      expect(FriendlyError.isTransient(TimeoutException('x')), isTrue);
      expect(FriendlyError.isTransient(fe('aborted')), isTrue);
      expect(FriendlyError.isTransient(fe('permission-denied')), isFalse);
      expect(FriendlyError.isTransient(fe('not-found')), isFalse);
      expect(FriendlyError.isTransient(StateError('x')), isFalse);
    });

    test('loadErrorKey still gives the same answers', () {
      expect(loadErrorKey(fe('unavailable')), 'errorNetwork');
      expect(loadErrorKey(fe('permission-denied')), 'errorNoAccess');
      expect(loadErrorKey(StateError('x')), 'errorGeneric');
    });

    test('new message strings are in 12 languages', () {
      for (final e in friendlyErrorStrings.entries) {
        expect(e.value.length, 12, reason: e.key);
        expect(e.value.every((s) => s.trim().isNotEmpty), isTrue, reason: e.key);
      }
      for (final k in ['errorSession', 'errorNotFound', 'errorBusy', 'errorConflict']) {
        expect(friendlyErrorStrings.containsKey(k), isTrue);
      }
    });
  });

  group('withRetry', () {
    final sleeps = <Duration>[];
    Future<void> fakeSleep(Duration d) async => sleeps.add(d);
    setUp(sleeps.clear);

    test('returns at once when it works', () async {
      var calls = 0;
      expect(await withRetry(() async => ++calls, sleep: fakeSleep), 1);
      expect(sleeps, isEmpty);
    });

    test('retries a transient failure with doubling pauses', () async {
      var calls = 0;
      final v = await withRetry(() async {
        calls++;
        if (calls < 3) throw fe('unavailable');
        return 'ok';
      }, sleep: fakeSleep);
      expect((v, calls), ('ok', 3));
      expect(sleeps, [const Duration(milliseconds: 400), const Duration(milliseconds: 800)]);
    });

    test('gives up after the last try and rethrows the last error', () async {
      var calls = 0;
      await expectLater(withRetry(() async {
        calls++;
        throw fe('unavailable');
      }, attempts: 2, sleep: fakeSleep), throwsA(isA<FirebaseException>()));
      expect(calls, 2);
      expect(sleeps.length, 1);
    });

    test('a permission error is not retried', () async {
      var calls = 0;
      await expectLater(withRetry(() async {
        calls++;
        throw fe('permission-denied');
      }, sleep: fakeSleep), throwsA(isA<FirebaseException>()));
      expect(calls, 1);
    });

    test('a hanging call times out and counts as transient', () async {
      var calls = 0;
      final v = await withRetry(() {
        calls++;
        return calls == 1 ? Completer<int>().future : Future.value(7);
      }, timeout: const Duration(milliseconds: 20), sleep: fakeSleep);
      expect((v, calls), (7, 2));
    });

    test('retryIf overrides the default', () async {
      var calls = 0;
      await expectLater(withRetry(() async {
        calls++;
        throw StateError('x');
      }, attempts: 3, retryIf: (_) => true, sleep: fakeSleep), throwsStateError);
      expect(calls, 3);
    });
  });

  group('ErrorState', () {
    testWidgets('shows the friendly message, no retry without a callback', (t) async {
      await t.pumpWidget(host(ErrorState(error: fe('permission-denied'))));
      expect(find.text(trEn('errorNoAccess')), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('with onRetry shows Retry and calls it', (t) async {
      var n = 0;
      await t.pumpWidget(host(ErrorState(error: fe('not-found'), onRetry: () => n++)));
      expect(find.text(trEn('errorNotFound')), findsOneWidget);
      await t.tap(find.text('Retry'));
      expect(n, 1);
    });

    testWidgets('offline says offline', (t) async {
      ConnectivityService.online.value = false;
      await t.pumpWidget(host(ErrorState(error: fe('internal'))));
      expect(find.text(trEn('errorOffline')), findsOneWidget);
    });

    testWidgets('compact variant', (t) async {
      await t.pumpWidget(host(ErrorState(error: TimeoutException('x'), compact: true)));
      expect(find.text(trEn('errorNetwork')), findsOneWidget);
    });
  });

  group('slow first snapshot', () {
    testWidgets('after 8 seconds the spinner becomes the "taking longer" message with Retry', (t) async {
      final never = StreamController<int>();
      addTearDown(never.close);
      await t.pumpWidget(host(LiveStream<int>(stream: () => never.stream, builder: (c, d) => Text('$d'))));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.pump(const Duration(seconds: 7));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.pump(const Duration(seconds: 2));
      expect(find.text(trEn('errorSlow')), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('empty states', () {
    testWidgets('flagged users list uses the shared empty state', (t) async {
      Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'admin1');
      t.view.physicalSize = const Size(800, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(home: LanguageScope(notifier: languageNotifier, child: const FlaggedUsersScreen())));
      await settle(t);
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text(trEn('noFlaggedUsers')), findsOneWidget);
    });
  });
}

String trEn(String key) => T.get(key, AppLanguage.english);
