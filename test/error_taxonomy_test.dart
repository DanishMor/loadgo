import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/errors/friendly_error.dart';
import 'package:transport_app/core/l10n/l10n.dart';

/// MASTER-6 Task 41: every failure has a friendly, translated sentence.
void main() {
  const codes = {
    'permission-denied': 'errorNoAccess',
    'unauthenticated': 'errorSession',
    'user-token-expired': 'errorSession',
    'unavailable': 'errorNetwork',
    'deadline-exceeded': 'errorNetwork',
    'network-request-failed': 'errorNetwork',
    'not-found': 'errorNotFound',
    'resource-exhausted': 'errorBusy',
    'aborted': 'errorBusy',
    'already-exists': 'errorConflict',
    'failed-precondition': 'errorConflict',
    'internal': 'errorGeneric',
    'data-loss': 'errorGeneric',
    'invalid-argument': 'errorGeneric',
  };

  test('each Firebase code maps to the right sentence', () {
    codes.forEach((code, key) => expect(FriendlyError.of(FirebaseException(plugin: 'cloud_firestore', code: code)), key, reason: code));
    expect(FriendlyError.of(TimeoutException('slow')), 'errorNetwork');
    expect(FriendlyError.of(StateError('x')), 'errorGeneric');
    expect(FriendlyError.of(null), 'errorGeneric');
  });

  test('only network and busy are worth a retry', () {
    expect(FriendlyError.isTransient(FirebaseException(plugin: 'p', code: 'unavailable')), isTrue);
    expect(FriendlyError.isTransient(FirebaseException(plugin: 'p', code: 'resource-exhausted')), isTrue);
    expect(FriendlyError.isTransient(FirebaseException(plugin: 'p', code: 'permission-denied')), isFalse);
  });

  test('every sentence exists in all 12 languages and never shows a code or class name', () {
    for (final key in {...codes.values, 'somethingWrong'}) {
      for (final lang in AppLanguage.values) {
        final t = T.get(key, lang);
        expect(t, isNotEmpty, reason: '$key $lang');
        expect(t.contains('Exception') || t.contains('permission-denied') || t.contains('FirebaseException'), isFalse, reason: '$key $lang');
      }
    }
  });

  test('no screen prints a raw exception to the person', () {
    final bad = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        if (l.trimLeft().startsWith('//') || l.contains('debugPrint')) continue;
        if (RegExp(r"(showSnack|SnackBar|Text)\([^;]*(\$e\b|\$\{e\}|\$error\b|e\.toString\(\)|error\.toString\(\)|\be\.message\b)").hasMatch(l)) bad.add('${f.path}:${i + 1}');
      }
    }
    // The admin health screen shows a stored log line for the owner, not a live exception.
    bad.remove('lib/admin/admin_health_screen.dart:79');
    // Two admin lists join their own field values (`where((e) => e.toString()...)`), not errors.
    bad.removeWhere((b) => b.startsWith('lib/admin/admin_lists.dart:'));
    expect(bad, isEmpty, reason: 'use errorText(context, error): $bad');
  });
}
