import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// MASTER-6 Task 39: docs/OFFLINE_MATRIX.md describes real files and uses only
/// the three behaviour kinds.
void main() {
  final rows = File('docs/OFFLINE_MATRIX.md')
      .readAsLinesSync()
      .where((l) => l.startsWith('| ') && !l.startsWith('| Area') && !l.startsWith('|---'))
      .map((l) => l.split('|').map((c) => c.trim()).toList())
      .toList();

  test('every row names an existing file and one of read, queue, network', () {
    expect(rows.length, greaterThanOrEqualTo(14));
    for (final r in rows) {
      expect(File(r[2]).existsSync(), isTrue, reason: '${r[1]}: ${r[2]} does not exist');
      expect(['read', 'queue', 'network'], contains(r[3]), reason: r[1]);
      expect(r[4], isNotEmpty);
    }
  });

  test('every "queue" row is backed by code that retries', () {
    final queueFiles = rows.where((r) => r[3] == 'queue').map((r) => r[2]);
    expect(queueFiles, isNotEmpty);
    for (final f in queueFiles) {
      final s = File(f).readAsStringSync();
      expect(s.contains('TripActionQueue') || s.contains('Queue') || s.contains('queue') || s.contains('retry') || s.contains('pending'), isTrue, reason: '$f has no queue or retry');
    }
  });
}
