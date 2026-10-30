import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';

/// E12: the voice rules of docs/COPY_DECK.md, checked on every English, Hindi
/// and Hinglish string (the languages the owner reads; the other nine are
/// translated from these and reviewed by native readers).
void main() {
  const langs = [AppLanguage.english, AppLanguage.hindi, AppLanguage.hinglish];

  /// Greetings may keep one exclamation mark; nothing else shouts.
  const exclamationOk = {'asGreeting'};

  final rules = <String, RegExp>{
    'no "Submit" button (use a verb for the action)': RegExp(r'^\s*submit\s*$', caseSensitive: false),
    'no "bhai" / "uncle" (name or "driver")': RegExp(r'\b(bhai|bhaiya|uncle)\b', caseSensitive: false),
    'no promises the app cannot keep': RegExp(r'100\s*%|guaranteed|risk[- ]free|fully insured|sabse safe', caseSensitive: false),
    'no "successfully" (say what happened)': RegExp(r'successfully|सफलतापूर्वक', caseSensitive: false),
    'no "oops"': RegExp(r'\b(oops|whoops|uh oh)\b', caseSensitive: false),
    'no raw technical words': RegExp(r'\bexception\b|stack ?trace|null check', caseSensitive: false),
    '"aap", never "tum" / "tu" (Hindi)': RegExp(r'(^|\s)(तुम|तू|तुम्हारा|तुम्हें|तेरा)(?=\s|$|[,।?])'),
    '"aap", never "tum" (Hinglish)': RegExp(r'\b(tum|tumhara|tumhe|tera)\b', caseSensitive: false),
  };

  for (final r in rules.entries) {
    test(r.key, () {
      final bad = <String>[];
      for (final e in T.data.entries) {
        for (final l in langs) {
          final s = e.value[l];
          if (s != null && r.value.hasMatch(s)) bad.add('${e.key} (${l.name}): $s');
        }
      }
      expect(bad, isEmpty);
    });
  }

  test('no exclamation marks outside greetings, and never two in a row', () {
    final bad = <String>[];
    for (final e in T.data.entries) {
      for (final l in langs) {
        final s = e.value[l];
        if (s == null) continue;
        if (s.contains('!!') || (s.contains('!') && !exclamationOk.contains(e.key))) bad.add('${e.key} (${l.name}): $s');
      }
    }
    expect(bad, isEmpty);
  });
}
