import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/app_info.dart';
import 'package:transport_app/core/l10n/l10n.dart';

import '../tool/apply_app_info.dart' as apply;

/// The app name lives in lib/core/app_info.dart only (docs/NAMING.md).
void main() {
  test('the platform files and the hosting pages match app_info.dart', () {
    expect(apply.outOfDate('.'), isEmpty, reason: 'run: dart run tool/apply_app_info.dart');
  });

  test('app_info is complete: a name and a tagline for every language', () {
    expect(AppInfo.name.trim(), isNotEmpty);
    expect(AppInfo.nameInLanguage.length, AppLanguage.values.length);
    expect(AppInfo.taglines.length, AppLanguage.values.length);
    expect(AppInfo.nameInLanguage.every((n) => n.trim().isNotEmpty), isTrue);
    expect(AppInfo.taglines.every((n) => n.trim().isNotEmpty), isTrue);
    expect(AppInfo.nameInLanguage[AppLanguage.english.index], AppInfo.name);
    expect(AppInfo.taglines[AppLanguage.english.index], AppInfo.tagline);
    expect(AppInfo.description.trim(), isNotEmpty);
  });

  test('the strings take the name and the tagline from app_info', () {
    for (final l in AppLanguage.values) {
      expect(T.get('welcome', l), contains(AppInfo.nameInLanguage[l.index]), reason: l.name);
      expect(T.get('tagline', l), AppInfo.taglines[l.index], reason: l.name);
    }
    expect(AppInfo.fill('Hello {app}!', AppLanguage.hindi.index), 'Hello ${AppInfo.nameInLanguage[1]}!');
    expect(AppInfo.fill('No token', 0), 'No token');
    for (final e in T.data.entries) {
      for (final v in e.value.values) {
        expect(v.contains('{app}'), isFalse, reason: '${e.key} still holds an unfilled {app}');
      }
    }
  });

  test('no translation table writes the name itself: they use {app}', () {
    final bad = <String>[];
    for (final f in Directory('lib/core/l10n').listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final text = f.readAsStringSync();
      for (final name in {AppInfo.name, ...AppInfo.nameInLanguage}) {
        if (text.contains(name)) bad.add('${f.path}: $name');
      }
    }
    expect(bad, isEmpty);
  });

  test('no screen, text or share string in lib/ spells the name: it comes from AppInfo', () {
    final literal = RegExp("'[^'\\n]*(?<![A-Za-z])${RegExp.escape(AppInfo.name)}(?![a-z])[^'\\n]*'");
    final bad = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      if (f.path.endsWith('lib/core/app_info.dart') || f.path.contains('lib/core/l10n/')) continue;
      var n = 0;
      for (final line in f.readAsLinesSync()) {
        n++;
        final t = line.trimLeft();
        if (t.startsWith('//')) continue;
        final code = t.contains(' // ') ? t.substring(0, t.indexOf(' // ')) : t;
        if (literal.hasMatch(code)) bad.add('${f.path}:$n: $t');
      }
    }
    expect(bad, isEmpty);
  });

  test('hosting pages carry the name and have no leftover token', () {
    for (final f in Directory('hosting').listSync().whereType<File>().where((f) => f.path.endsWith('.html'))) {
      final text = f.readAsStringSync();
      expect(text.contains('{{'), isFalse, reason: f.path);
      expect(text.contains(AppInfo.name), isTrue, reason: f.path);
    }
  });

  test('NAMING.md lists the files a rename touches', () {
    final doc = File('docs/NAMING.md').readAsStringSync();
    for (final p in [
      'lib/core/app_info.dart',
      'tool/apply_app_info.dart',
      'tool/templates/hosting',
      'android/app/src/main/AndroidManifest.xml',
      'ios/Runner/Info.plist',
      'web/index.html',
      'web/manifest.json',
      'hosting/privacy.html',
      'hosting/terms.html',
    ]) {
      expect(doc, contains(p));
    }
  });
}
