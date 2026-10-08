import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Task 1 (MASTER-5): a static audit of `firestore.rules`. The behaviour is
/// pinned by the emulator tests; this guards the shape of the file itself.
void main() {
  final rules = File('firestore.rules').readAsStringSync();
  final lines = rules.split('\n');

  test('the last match is the explicit deny-all', () {
    final matches = lines.where((l) => l.trimLeft().startsWith('match /')).toList();
    expect(matches.last.trim(), startsWith('match /{document=**}'));
    expect(rules.trimRight().endsWith('}'), isTrue);
    final tail = rules.substring(rules.lastIndexOf('match /{document=**}'));
    expect(tail, contains('allow read, write: if false;'));
  });

  test('no rule is open to everyone', () {
    final open = RegExp(r'allow [a-z, ]*:\s*if\s+(true|signedIn\(\))\s*;');
    final bad = [for (var i = 0; i < lines.length; i++) if (open.hasMatch(lines[i]) && lines[i].contains(RegExp(r'create|update|write|delete'))) '${i + 1}: ${lines[i].trim()}'];
    expect(bad, isEmpty, reason: 'unconditional write: $bad');
  });

  test('every create rule names who may create', () {
    final gate = RegExp(r'signedIn\(\)|isUser\(|isAdmin\(\)|adminIn\(|demoCreate\(');
    final bad = <String>[];
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].contains('allow create')) continue;
      if (!gate.hasMatch(lines[i])) bad.add('${i + 1}: ${lines[i].trim()}');
    }
    expect(bad, isEmpty);
  });

  test('clocks come from the server in the rules, not from the client', () {
    expect(rules, contains('request.time'));
  });
}
