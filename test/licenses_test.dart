import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// E5: no package, font or asset folder without a licence row in docs/LICENSES.md.
void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync().replaceAll('\r\n', '\n');
  final doc = File('docs/LICENSES.md').readAsStringSync();
  const allowed = {'MIT', 'BSD-2-Clause', 'BSD-3-Clause', 'Apache-2.0'};

  List<String> section(String name) {
    final m = RegExp('^$name:\\n([\\s\\S]*?)(?=^\\S)', multiLine: true).firstMatch(pubspec)!;
    return RegExp(r'^  ([a-z0-9_]+):', multiLine: true).allMatches(m.group(1)!).map((x) => x.group(1)!).where((n) => n != 'flutter' && n != 'flutter_test').toList();
  }

  test('every package has a row with an allowed licence', () {
    final names = [...section('dependencies'), ...section('dev_dependencies')];
    expect(names.length, greaterThan(20));
    for (final n in names) {
      final row = RegExp('^\\| `$n` \\| [^|]+ \\| ([^|]+) \\|', multiLine: true).firstMatch(doc);
      expect(row, isNotNull, reason: '$n is not in docs/LICENSES.md');
      expect(allowed, contains(row!.group(1)!.trim()), reason: '$n: licence ${row.group(1)}');
    }
  });

  test('no row for a package that is no longer used', () {
    final names = {...section('dependencies'), ...section('dev_dependencies')};
    final pkgTable = doc.split('## Packages').last.split('## Fonts').first;
    for (final m in RegExp(r'^\| `([a-z0-9_]+)` \|', multiLine: true).allMatches(pkgTable)) {
      expect(names, contains(m.group(1)), reason: '${m.group(1)} is listed but not in pubspec.yaml');
    }
  });

  test('every bundled font is listed with an open licence and its licence file ships', () {
    final fonts = RegExp(r'asset: (assets/fonts/\S+)').allMatches(pubspec).map((m) => m.group(1)!).toSet();
    expect(fonts, isNotEmpty);
    for (final f in fonts) {
      expect(doc, contains('| `$f` | SIL OFL 1.1 |'), reason: f);
    }
    for (final f in Directory('assets/fonts').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.ttf'))) {
      final p = f.path.replaceAll('\\', '/');
      expect(doc, contains('`$p`'), reason: '$p is in assets but not in docs/LICENSES.md');
    }
    expect(File('assets/fonts/LICENSE.txt').existsSync(), isTrue);
    expect(File('assets/fonts/mukta/OFL.txt').existsSync(), isTrue);
  });

  test('every asset folder has a licence row', () {
    for (final d in Directory('assets').listSync().whereType<Directory>()) {
      final name = d.path.replaceAll('\\', '/');
      if (name.endsWith('/fonts')) continue;
      expect(doc, contains('`$name/`'), reason: '$name has no licence row');
    }
  });
}
