import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/theme_guard.dart';

/// L7: outside lib/core/theme nothing may add a hard-coded `Color(0x...)` or a
/// `TextStyle(`. Older screens are on a baseline (docs/THEME_EXCEPTIONS.md);
/// the numbers can only go down.
void main() {
  final baseline = <String, Map<String, dynamic>>{
    for (final e in (jsonDecode(File('test/theme_guard_baseline.json').readAsStringSync()) as Map<String, dynamic>).entries) e.key: e.value as Map<String, dynamic>,
  };
  final now = scan();

  test('no file has more hard-coded colours or text styles than its baseline', () {
    final worse = <String>[];
    for (final e in now.entries) {
      final b = baseline[e.key];
      final bc = (b?['colors'] as int?) ?? 0, bs = (b?['styles'] as int?) ?? 0;
      if (e.value.colors > bc) worse.add('${e.key}: ${e.value.colors} colours (baseline $bc)');
      if (e.value.styles > bs) worse.add('${e.key}: ${e.value.styles} text styles (baseline $bs)');
    }
    expect(worse, isEmpty, reason: 'Use DsColors / AppPalette / the theme and DsType instead (docs/BRAND.md). Existing screens may only go down.');
  });

  test('the baseline lists no file that no longer exists', () {
    final gone = [for (final k in baseline.keys) if (!File(k).existsSync()) k];
    expect(gone, isEmpty, reason: 'run: dart run tool/theme_guard.dart --write');
  });

  test('docs/THEME_EXCEPTIONS.md is the table of the baseline', () {
    final doc = File('docs/THEME_EXCEPTIONS.md').readAsStringSync();
    for (final k in baseline.keys) {
      expect(doc.contains('`$k`'), isTrue, reason: '$k missing in docs/THEME_EXCEPTIONS.md');
    }
    final totalColors = baseline.values.fold<int>(0, (a, b) => a + (b['colors'] as int));
    final totalStyles = baseline.values.fold<int>(0, (a, b) => a + (b['styles'] as int));
    expect(doc, contains('**$totalColors** colours, **$totalStyles** text styles'));
  });

  test('the scanner counts colours and styles and skips comments and the theme folder', () {
    final dir = Directory.systemTemp.createTempSync('guard');
    addTearDown(() => dir.deleteSync(recursive: true));
    final lib = Directory('${dir.path}/lib/feature')..createSync(recursive: true);
    Directory('${dir.path}/lib/core/theme').createSync(recursive: true);
    File('${lib.path}/a.dart').writeAsStringSync('''
// Color(0xFF000000) in a comment
final a = Color(0xFF112233);
final b = const TextStyle(fontSize: 12);
final c = DefaultTextStyle(style: x);
final d = Theme.of(context).textTheme.bodyLarge!.copyWith(color: p.text);
''');
    File('${dir.path}/lib/core/theme/t.dart').writeAsStringSync('final a = Color(0xFF112233); final b = TextStyle();');
    final found = scan('${dir.path}/lib');
    expect(found.length, 1);
    final c = found.values.single;
    expect(c.colors, 1);
    expect(c.styles, 1);
  });

  test('the design system files themselves are exempt and exist', () {
    expect(File('lib/core/theme/design_tokens.dart').existsSync(), isTrue);
    expect(now.keys.where((k) => k.startsWith('lib/core/theme/')), isEmpty);
  });
}
