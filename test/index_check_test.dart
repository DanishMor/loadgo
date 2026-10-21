import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Z4: every Firestore query in lib/ that needs a composite index has one in firestore.indexes.json.
/// tool/check_indexes.js does the scan (docs/INDEX_CHECK.md lists what it cannot see).
void main() {
  ProcessResult run(List<String> args) => Process.runSync('node', ['tool/check_indexes.js', ...args]);

  test('no query in lib/ lacks its composite index', () {
    final r = run([]);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
  });

  test('the checker does catch a new query without an index', () {
    final dir = Directory.systemTemp.createTempSync('idxchk');
    try {
      Directory('${dir.path}/lib').createSync();
      File('${dir.path}/lib/a.dart').writeAsStringSync("void f(){ db.collection('zz').where('a', isEqualTo: 1).orderBy('b', descending: true).snapshots(); }");
      File('${dir.path}/firestore.indexes.json').writeAsStringSync('{"indexes":[]}');
      final r = run(['--root', dir.path]);
      expect(r.exitCode, 1);
      expect('${r.stdout}', contains('MISSING'));
      File('${dir.path}/firestore.indexes.json').writeAsStringSync(
          '{"indexes":[{"collectionGroup":"zz","queryScope":"COLLECTION","fields":[{"fieldPath":"a","order":"ASCENDING"},{"fieldPath":"b","order":"DESCENDING"}]}]}');
      expect(run(['--root', dir.path]).exitCode, 0);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
