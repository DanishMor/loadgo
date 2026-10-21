import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Z14: tool/translation_apply.js on a copy of two files: dry run by default, placeholder check, stops on a mistake.
void main() {
  late Directory dir;
  const table = "const Map<String, List<String>> t = {\n  'k1': ['Hello {name}', 'नमस्ते {name}', 'Namaste {name}', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i'],\n  'k2': ['Two', 'दो', 'Do', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i'],\n};\n";

  setUp(() {
    dir = Directory.systemTemp.createTempSync('trapply');
    Directory('${dir.path}/lib/core/l10n').createSync(recursive: true);
    Directory('${dir.path}/docs/translation').createSync(recursive: true);
    File('${dir.path}/lib/core/l10n/x_strings.dart').writeAsStringSync(table);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  void csv(String fix1, [String fix2 = '']) => File('${dir.path}/docs/translation/hi.csv').writeAsStringSync(
      'key,english,text,fix,status\r\nk1,Hello {name},नमस्ते {name},"$fix1",pending\r\nk2,Two,दो,"$fix2",pending\r\n');

  ProcessResult run(List<String> extra) => Process.runSync('node', ['tool/translation_apply.js', '--root', dir.path, '--lang', 'hi', ...extra]);
  String file() => File('${dir.path}/lib/core/l10n/x_strings.dart').readAsStringSync();

  test('dry run is the default: it prints the change and writes nothing', () {
    csv('प्रणाम {name}');
    final r = run([]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect('${r.stdout}', contains('would change hi/k1'));
    expect(file(), table);
  });

  test('--apply writes the fixed text in the right language slot only', () {
    csv('प्रणाम {name}', "दो'ट");
    expect(run(['--apply']).exitCode, 0);
    expect(file(), contains("'Hello {name}', 'प्रणाम {name}', 'Namaste {name}'"));
    expect(file(), contains(r"'Two', 'दो\'ट', 'Do'"));
  });

  test('a fix with different placeholders stops everything and writes nothing', () {
    csv('प्रणाम {nam}', 'दो दो');
    final r = run(['--apply']);
    expect(r.exitCode, 1);
    expect('${r.stderr}', contains('placeholders differ'));
    expect(file(), table);
  });

  test('an unknown key stops the run', () {
    File('${dir.path}/docs/translation/hi.csv').writeAsStringSync('key,english,text,fix,status\r\nnope,x,y,"z",pending\r\n');
    final r = run(['--apply']);
    expect(r.exitCode, 1);
    expect('${r.stderr}', contains('key not found'));
  });

  test('the real review files exist: merged file and 12 language files with the same keys', () {
    final all = File('docs/TRANSLATION_REVIEW_ALL.csv').readAsStringSync();
    expect(all, contains('key,language,text,reviewer,status'));
    final counts = <int>{};
    for (final l in ['en', 'hi', 'hinglish', 'kn', 'ta', 'te', 'mr', 'gu', 'bn', 'pa', 'ks', 'ur']) {
      counts.add(File('docs/translation/$l.csv').readAsLinesSync().length);
    }
    expect(counts.length, 1, reason: 'every language file has the same number of rows');
    // no duplicate key+language rows in the merged file
    final seen = <String>{};
    for (final line in all.split('\n').skip(1)) {
      final m = RegExp(r'^"?([A-Za-z0-9_]+)"?,(\w+),').firstMatch(line);
      if (m != null) expect(seen.add('${m[1]}|${m[2]}'), isTrue, reason: 'duplicate ${m[1]} ${m[2]}');
    }
  });

  test('a dry run on the real repo with no fixes changes nothing', () {
    final r = Process.runSync('node', ['tool/translation_apply.js']);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect('${r.stdout}', contains('0 change(s)'));
  });
}
