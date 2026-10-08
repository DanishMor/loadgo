import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';

/// Every literal key passed to tr() / trf() exists in the translation tables.
/// A typo or a forgotten table shows the raw key on screen (Phase 7 gap).
void main() {
  test('every tr()/trf() key written in lib/ has a translation', () {
    final call = RegExp(r'''\btrf?\(\s*[A-Za-z_][A-Za-z0-9_.]*\s*,\s*'([A-Za-z0-9_]+)'\s*[,)]''');
    final missing = <String>{};
    var seen = 0;
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      if (f.path.contains('lib/core/l10n/')) continue;
      final text = f.readAsStringSync();
      for (final m in call.allMatches(text)) {
        seen++;
        final key = m.group(1)!;
        if (!T.data.containsKey(key)) missing.add('$key  (${f.path})');
      }
    }
    expect(seen, greaterThan(500), reason: 'the scan must really see the tr() calls');
    expect(missing, isEmpty);
  });

  test('keys passed as titleKey / labelKey / textKey exist too', () {
    final named = RegExp("\\b(?:titleKey|labelKey|subtitleKey|messageKey|hintKey|bodyKey)\\s*:\\s*'([A-Za-z0-9_]+)'");
    final missing = <String>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      if (f.path.contains('lib/core/l10n/')) continue;
      for (final m in named.allMatches(f.readAsStringSync())) {
        final key = m.group(1)!;
        if (!T.data.containsKey(key)) missing.add('$key  (${f.path})');
      }
    }
    expect(missing, isEmpty);
  });
}
