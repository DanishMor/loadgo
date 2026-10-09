import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// MASTER-5 Task 9: a ratchet on Firestore listeners. A listener that reads a
/// whole query (no `limit`, not a single document) costs reads for as long as
/// the screen is open and grows with the user's history. The number may only
/// go down; a new unbounded listener needs a reason and a raised budget here.
/// The list of the existing ones with the plan to bound them is in
/// docs/COST_WATCH.md.
void main() {
  int unbounded() {
    var n = 0;
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final s = f.readAsStringSync();
      for (final m in RegExp(r'\.snapshots\(\)').allMatches(s)) {
        final start = s.lastIndexOf(';', m.start) + 1;
        final seg = s.substring(start, m.start);
        final tail = seg.split('.where').first;
        final single = tail.substring(tail.length > 80 ? tail.length - 80 : 0).contains('.doc(');
        if (!seg.contains('limit(') && !single) n++;
      }
    }
    return n;
  }

  test('the number of unbounded listeners does not grow', () {
    const budget = 69; // M6: one more admin/pilot list (rows are few; see COST_WATCH.md)
    expect(unbounded(), lessThanOrEqualTo(budget), reason: 'add .limit(...) or document why in COST_WATCH.md and raise the budget');
  });

  test('every screen that listens cancels its subscription', () {
    // StreamBuilder cancels itself. A raw `.listen(` in a State needs a cancel/dispose.
    final bad = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final s = f.readAsStringSync();
      if (f.path.endsWith('voice_input.dart')) continue; // a speech-engine method named listen, not a stream
      if (!s.contains('extends State<') || !RegExp(r'\.listen\(').hasMatch(s)) continue;
      if (!s.contains('.cancel(') && !s.contains('cancelAll') && !s.contains('subs')) bad.add(f.path);
    }
    expect(bad, isEmpty, reason: 'State classes that listen but never cancel: $bad');
  });
}
