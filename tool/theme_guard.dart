// Counts hard-coded colours and text styles outside lib/core/theme (L7).
//
//   dart run tool/theme_guard.dart            prints the table
//   dart run tool/theme_guard.dart --write    rewrites test/theme_guard_baseline.json
//                                             and docs/THEME_EXCEPTIONS.md
//
// test/theme_guard_test.dart fails when a file has MORE than its baseline, or a
// file that is not in the baseline has any. Moving a screen to the design
// system lowers a count; run --write then to lock the lower number in.
import 'dart:convert';
import 'dart:io';

final _color = RegExp(r'Color\(\s*0x[0-9A-Fa-f]+\s*\)');
final _style = RegExp(r'(?<![A-Za-z_])TextStyle\(');

class Count {
  final int colors;
  final int styles;
  const Count(this.colors, this.styles);
  bool get any => colors > 0 || styles > 0;
  Map<String, int> toJson() => {'colors': colors, 'styles': styles};
}

/// File (with `/`) -> counts, only files with at least one hit. Comments are skipped.
Map<String, Count> scan([String root = 'lib']) {
  final out = <String, Count>{};
  for (final f in Directory(root).listSync(recursive: true).whereType<File>()) {
    final path = f.path.replaceAll('\\', '/');
    if (!path.endsWith('.dart') || path.startsWith('lib/core/theme/') || path.contains('/lib/core/theme/')) continue;
    var colors = 0, styles = 0;
    for (final line in f.readAsLinesSync()) {
      if (line.trimLeft().startsWith('//')) continue;
      colors += _color.allMatches(line).length;
      styles += _style.allMatches(line).length;
    }
    final c = Count(colors, styles);
    if (c.any) out[path.startsWith('lib/') ? path : path.substring(path.indexOf('lib/'))] = c;
  }
  return Map.fromEntries(out.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
}

void main(List<String> args) {
  final now = scan();
  final totalColors = now.values.fold<int>(0, (a, b) => a + b.colors);
  final totalStyles = now.values.fold<int>(0, (a, b) => a + b.styles);
  if (args.contains('--write')) {
    final json = const JsonEncoder.withIndent('  ').convert({for (final e in now.entries) e.key: e.value.toJson()});
    File('test/theme_guard_baseline.json').writeAsStringSync('$json\n');
    final b = StringBuffer()
      ..writeln('# Theme exceptions (L7)')
      ..writeln()
      ..writeln('Outside `lib/core/theme/` nothing should spell a colour (`Color(0x...)`) or build a `TextStyle`; colours come from `DsColors` / `AppPalette` / the theme and text from `DsType` / `Theme.of(context).textTheme` (`docs/BRAND.md`). The screens written before the design system still do, so this list is the **baseline**: `test/theme_guard_test.dart` fails if a file gets more hard-coded colours or styles than listed here, or if a file that is not listed gets any. Moving a screen onto the shared components (Phase 3) lowers its number; then run `dart run tool/theme_guard.dart --write` to lock it in. The goal is an empty table.')
      ..writeln()
      ..writeln('Total: **$totalColors** colours, **$totalStyles** text styles in **${now.length}** files.')
      ..writeln()
      ..writeln('| File | `Color(0x...)` | `TextStyle(` |')
      ..writeln('|---|---|---|');
    for (final e in now.entries) {
      b.writeln('| `${e.key}` | ${e.value.colors} | ${e.value.styles} |');
    }
    File('docs/THEME_EXCEPTIONS.md').writeAsStringSync(b.toString());
    stdout.writeln('Wrote the baseline and docs/THEME_EXCEPTIONS.md ($totalColors colours, $totalStyles styles, ${now.length} files).');
    return;
  }
  for (final e in now.entries) {
    stdout.writeln('${e.value.colors.toString().padLeft(4)} ${e.value.styles.toString().padLeft(4)}  ${e.key}');
  }
  stdout.writeln('total: $totalColors colours, $totalStyles styles, ${now.length} files');
}
