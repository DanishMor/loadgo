import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// MASTER-6 Task 37: cheap guards that keep the app light. The profile-mode
/// checks that need a phone are in docs/PERFORMANCE.md.
void main() {
  test('assets stay small: fonts only, under 3 MB in total, no single file over 700 KB', () {
    var total = 0;
    for (final f in Directory('assets').listSync(recursive: true).whereType<File>()) {
      final n = f.lengthSync();
      total += n;
      expect(n, lessThan(700 * 1024), reason: '${f.path} is ${n ~/ 1024} KB; shrink it or subset the font');
    }
    expect(total, lessThan(3 * 1024 * 1024));
  });

  test('lists built from a loop inside ListView(children:) do not grow (use ListView.builder for long lists)', () {
    var n = 0;
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final s = f.readAsStringSync();
      for (final m in RegExp(r'ListView\(').allMatches(s)) {
        final seg = s.substring(m.start, (m.start + 600).clamp(0, s.length));
        if (RegExp(r'\n\s+for \(final').hasMatch(seg)) n++;
      }
    }
    // Today's count: screens whose lists are short or already capped by a query limit.
    expect(n, lessThanOrEqualTo(52), reason: 'a list that can be long belongs in ListView.builder');
  });

  test('shrinkWrap lists do not grow (they build every row at once)', () {
    var n = 0;
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      n += 'shrinkWrap: true'.allMatches(f.readAsStringSync()).length;
    }
    expect(n, lessThanOrEqualTo(13));
  });

  test('no network image is loaded without a size hint (decoding full photos on low-end phones)', () {
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final s = f.readAsStringSync();
      for (final m in RegExp(r'Image\.network\(([^;]*?)\)[,;]').allMatches(s)) {
        expect(m.group(1)!.contains('cacheWidth') || m.group(1)!.contains('width:'), isTrue, reason: '${f.path}: add width/cacheWidth to Image.network');
      }
    }
  });
}
