import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/main.dart';

void main() {
  test('every translation key has all 12 languages', () {
    final incomplete = <String>[
      for (final e in T.data.entries)
        if (AppLanguage.values.any((l) => (e.value[l] ?? '').isEmpty)) e.key,
    ];
    expect(incomplete, isEmpty);
  });
}
