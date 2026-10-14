import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/app_info.dart';

/// L1: the app is called "Load 20". The old display name must not be left in
/// anything a person can read: strings in lib/, hosting pages, the web files,
/// the Android label and the iOS texts. (Comments and the Dart class name
/// `LoadGoApp` are not shown to anyone.)
void main() {
  const oldName = 'LoadGo';

  test('the name and tagline are the new ones in app_info', () {
    expect(AppInfo.name, 'Load 20');
    expect(AppInfo.tagline, 'Maal bhejo, bharosa ke saath');
    expect(AppInfo.nameInLanguage.length, 12);
    for (final n in AppInfo.nameInLanguage) {
      expect(n.contains('20'), isTrue, reason: n);
      expect(n.contains(oldName), isFalse, reason: n);
    }
  });

  test('no Dart string literal in lib/ spells the old name', () {
    final literal = RegExp('''(['"])[^'"\\n]*$oldName[^'"\\n]*\\1''');
    final bad = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final path = f.path.replaceAll('\\', '/');
      var n = 0;
      for (final line in f.readAsLinesSync()) {
        n++;
        final code = line.trimLeft();
        if (code.startsWith('//')) continue;
        if (literal.hasMatch(line)) bad.add('$path:$n');
      }
    }
    expect(bad, isEmpty);
  });

  test('hosting pages, web files, Android label and iOS texts carry the new name only', () {
    final files = <File>[
      ...Directory('hosting').listSync().whereType<File>().where((f) => f.path.endsWith('.html')),
      File('web/index.html'),
      File('web/manifest.json'),
      File('android/app/src/main/AndroidManifest.xml'),
      File('ios/Runner/Info.plist'),
      File('functions/index.js'),
    ];
    final bad = [for (final f in files) if (f.readAsStringSync().contains(oldName)) f.path.replaceAll('\\', '/')];
    expect(bad, isEmpty);
    expect(File('android/app/src/main/AndroidManifest.xml').readAsStringSync(), contains('android:label="Load 20"'));
    expect(File('web/manifest.json').readAsStringSync(), contains('"short_name": "Load 20"'));
  });

  test('README and the Play listing drafts use the new name', () {
    for (final p in ['README.md', 'docs/PLAY_LISTING.md', 'docs/PLAY_STORE_CHECKLIST.md']) {
      final t = File(p).readAsStringSync();
      expect(t.contains(oldName), isFalse, reason: p);
      expect(t.contains('Load 20'), isTrue, reason: p);
    }
  });

  test('the package id is still the placeholder (only the display name changed)', () {
    expect(File('android/gradle.properties').readAsStringSync(), contains('loadgo.applicationId=com.example.transport_app'));
  });
}
