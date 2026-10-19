import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Part 5 (H18): a screen must not touch its State after an await without checking `mounted`.
/// A cheap source scan: a `setState(` that follows an `await` in the same method, with no `mounted` in between.
/// The two entries below were read by hand: the await is in a branch that returns.
void main() {
  const allowed = {
    'lib/customer/post_load_screen.dart',
    'lib/customer/v2/booking_wizard_screen.dart',
  };

  test('no setState after an await without a mounted check (two reviewed exceptions)', () {
    final hits = <String>{};
    final start = RegExp(r'^\s{2}[A-Za-z<>?,\s]+\s\w+\(.*\)\s*(async\s*)?\{\s*$');
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('setState(') || lines[i].contains('mounted')) continue;
        var s = i;
        while (s > 0 && !start.hasMatch(lines[s])) {
          s--;
        }
        var lastAwait = -1, lastMounted = -1;
        for (var k = s; k < i; k++) {
          if (lines[k].contains('await ')) lastAwait = k;
          if (lines[k].contains('mounted')) lastMounted = k;
        }
        if (lastAwait >= 0 && lastMounted < lastAwait) hits.add(f.path.replaceAll(r'\', '/'));
      }
    }
    expect(hits.difference(allowed), isEmpty, reason: 'check `mounted` after the await in these files');
  });

  test('null assertions (!) stay few: each new one should be a decision', () {
    var count = 0;
    final bang = RegExp(r'[A-Za-z_\)\]]!(\.|\)|;|,)');
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      for (final l in f.readAsLinesSync()) {
        if (!l.contains('!=') && bang.hasMatch(l)) count++;
      }
    }
    expect(count, lessThanOrEqualTo(400), reason: 'was 377 lines (this count includes a few ! in texts) when measured in Part 5 (H18)');
  });
}
