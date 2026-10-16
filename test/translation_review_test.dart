import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';

/// F38: the review file for the native reader is complete and in the right shape.
void main() {
  final lines = File('docs/TRANSLATION_REVIEW.csv').readAsStringSync().split(RegExp(r'\r?\n')).where((l) => l.isNotEmpty).toList();

  test('header, and every text has exactly the 12 language rows', () {
    expect(lines.first.replaceFirst('﻿', ''), 'key,file,language,text,reviewer_ok,reviewer_fix,reviewer_name');
    final langs = ['en', 'hi', 'hinglish', 'kn', 'ta', 'te', 'mr', 'gu', 'bn', 'pa', 'ks', 'ur'];
    final byKey = <String, List<String>>{};
    for (final l in lines.skip(1)) {
      final m = RegExp(r'^"([^"]+)","[^"]+",([a-z]+),').firstMatch(l);
      expect(m, isNotNull, reason: l);
      byKey.putIfAbsent(m!.group(1)!, () => []).add(m.group(2)!);
    }
    expect(byKey.length, greaterThan(100));
    byKey.forEach((k, v) => expect(v, langs, reason: k));
  });

  test('the new keys of the main areas are in the file and the app can still find them', () {
    final csv = lines.join('\n');
    for (final k in ['photoAdd', 'adminWebNotAdmin', 'serverStatusCheck', 'feat_paymentGateway']) {
      expect(csv, contains('"$k"'), reason: k);
      expect(T.get(k, AppLanguage.english), isNotEmpty, reason: k);
    }
  });

  test('the reader guide names the files that are not in the CSV', () {
    final doc = File('docs/TRANSLATION_REVIEW.md').readAsStringSync();
    expect(doc, contains('push_channels.xml'));
    expect(doc, contains('pushText.js'));
    expect(File('functions/src/pushText.js').existsSync(), isTrue);
  });
}
