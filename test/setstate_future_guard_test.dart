import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// `setState(() => _x = someFuture)` returns the Future from the closure, which
/// Flutter asserts against in debug builds (bug M6-B1). Use a block body.
void main() {
  test('no setState arrow assigns a Future-returning service call', () {
    final bad = RegExp(r'setState\(\(\) => _\w+ = [A-Z]\w+Service\.(?!contactsFrom)\w+\(');
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      if (bad.hasMatch(f.readAsStringSync())) hits.add(f.path);
    }
    expect(hits, isEmpty);
  });
}
