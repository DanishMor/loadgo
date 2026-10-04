import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/l10n/strings.dart';
import 'package:transport_app/main.dart';

void main() {
  test('every translation key has all 12 languages', () {
    final incomplete = <String>[
      for (final e in T.data.entries)
        if (AppLanguage.values.any((l) => (e.value[l] ?? '').isEmpty)) e.key,
    ];
    expect(incomplete, isEmpty);
  });

  test('feature string tables: 12 entries each, keys unique across tables', () {
    final seen = <String>{};
    final dupes = <String>[];
    for (final table in stringTables) {
      for (final e in table.entries) {
        expect(e.value.length, AppLanguage.values.length, reason: e.key);
        if (!seen.add(e.key)) dupes.add(e.key);
      }
    }
    expect(dupes, isEmpty);
  });
}
