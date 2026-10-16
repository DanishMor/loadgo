import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/features/features.dart';

/// F15: the switches the Cloud Functions look at are the same ones the Admin > Features screen writes.
void main() {
  List<String> serverFlags() {
    final src = File('functions/src/common.js').readAsStringSync();
    final block = RegExp(r'const FLAGS = Object\.freeze\(\[(.*?)\]\)', dotAll: true).firstMatch(src)!.group(1)!;
    return RegExp(r"'([A-Za-z]+)'").allMatches(block).map((m) => m.group(1)!).toList();
  }

  test('every function switch is in the app registry, OFF in both modes', () {
    final reg = {for (final s in Features.registry) s.key: s};
    final flags = serverFlags();
    expect(flags, isNotEmpty);
    for (final f in flags) {
      expect(reg.containsKey(f), isTrue, reason: '$f is missing in lib/core/features/features.dart');
      expect(reg[f]!.pilotOn, isFalse, reason: f);
      expect(reg[f]!.normalOn, isFalse, reason: f);
    }
  });

  test('docs/FUNCTIONS.md lists every switch and says nothing is deployed by Claude', () {
    final doc = File('docs/FUNCTIONS.md').readAsStringSync();
    for (final f in serverFlags()) {
      expect(doc, contains('`$f`'), reason: f);
    }
    expect(doc, contains('asia-south1'));
    expect(doc.toLowerCase(), contains('never runs'));
  });

  test('the functions are written for asia-south1 and Node 22', () {
    expect(File('functions/src/common.js').readAsStringSync(), contains("REGION = 'asia-south1'"));
    expect(File('functions/package.json').readAsStringSync(), contains('"node": "22"'));
    expect(File('functions/index.js').readAsStringSync(), contains('setGlobalOptions'));
  });
}
