import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';

/// TEST9: automatic language QA over every translation. It cannot judge the
/// quality of a sentence (that needs a person), but it catches the mistakes
/// machines can see: a placeholder lost or renamed in one language, an empty
/// or padded text, a text left in English where another script is expected,
/// and a stray script in English / Hinglish.
const _scripts = <AppLanguage, List<(int, int)>>{
  AppLanguage.hindi: [(0x0900, 0x097F)],
  AppLanguage.marathi: [(0x0900, 0x097F)],
  AppLanguage.bengali: [(0x0980, 0x09FF)],
  AppLanguage.punjabi: [(0x0A00, 0x0A7F)],
  AppLanguage.gujarati: [(0x0A80, 0x0AFF)],
  AppLanguage.tamil: [(0x0B80, 0x0BFF)],
  AppLanguage.telugu: [(0x0C00, 0x0C7F)],
  AppLanguage.kannada: [(0x0C80, 0x0CFF)],
  AppLanguage.urdu: [(0x0600, 0x06FF), (0x0750, 0x077F), (0xFB50, 0xFDFF), (0xFE70, 0xFEFF)],
  AppLanguage.kashmiri: [(0x0600, 0x06FF), (0x0750, 0x077F), (0xFB50, 0xFDFF), (0xFE70, 0xFEFF)],
};

bool _inScript(int c, List<(int, int)> ranges) => ranges.any((r) => c >= r.$1 && c <= r.$2);

bool _isLetter(int c) => (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

/// English text without placeholders, product names and acronyms.
String _plain(String s) => s.replaceAll(RegExp(r'\{\w+\}'), '').replaceAll(RegExp(r'\b[A-Z][A-Za-z]*[A-Z]\w*\b'), '');

/// Examples of data shown as typed (a JSON sample, an item list), kept in English on purpose.
const _sameOnPurpose = {'moversItemsHint', 'adminSupportConfigSub'};

void main() {
  final data = T.data;

  test('every key has a text in all 12 languages, without padding or leftover markers', () {
    final bad = <String>[];
    for (final e in data.entries) {
      for (final l in AppLanguage.values) {
        final t = e.value[l] ?? '';
        if (t.isEmpty || t != t.trim() || t.contains('TODO') || t.contains('??') || t.contains('\u0000')) bad.add('${e.key}/${l.name}');
      }
    }
    expect(bad, isEmpty);
  });

  test('placeholders {name} are the same in every language of a key', () {
    final bad = <String>[];
    final re = RegExp(r'\{(\w+)\}');
    for (final e in data.entries) {
      Set<String> names(AppLanguage l) => {for (final m in re.allMatches(e.value[l] ?? '')) m.group(1)!};
      final en = names(AppLanguage.english);
      for (final l in AppLanguage.values) {
        if (names(l).difference(en).isNotEmpty || en.difference(names(l)).isNotEmpty) bad.add('${e.key}/${l.name}: ${names(l)} vs $en');
      }
    }
    expect(bad, isEmpty);
  });

  test('English and Hinglish are written in Latin letters only', () {
    final bad = <String>[];
    for (final e in data.entries) {
      for (final l in [AppLanguage.english, AppLanguage.hinglish]) {
        final t = e.value[l] ?? '';
        if (t.runes.any((c) => c > 0x024F && c < 0x1F000 && !(c >= 0x2600 && c <= 0x27BF) && c != 0x2192 && c != 0x2022 && c != 0x00B7 && c != 0x20B9 && c != 0x2014 && c != 0x2013 && c != 0x2019 && c != 0x201C && c != 0x201D && c != 0x2026 && c != 0x2713 && c != 0x2605)) bad.add('${e.key}/${l.name}');
      }
    }
    expect(bad, isEmpty);
  });

  test('a sentence in an Indian-script language contains that script (not left in English)', () {
    final bad = <String>[];
    for (final e in data.entries) {
      final en = _plain(e.value[AppLanguage.english] ?? '');
      // Short labels and codes are often kept in English on purpose.
      if (en.runes.where(_isLetter).length < 8 || _sameOnPurpose.contains(e.key)) continue;
      for (final entry in _scripts.entries) {
        final t = e.value[entry.key] ?? '';
        if (!t.runes.any((c) => _inScript(c, entry.value))) bad.add('${e.key}/${entry.key.name}');
      }
    }
    expect(bad, isEmpty);
  });

  test('a translation is not just the English text with the script of another language mixed in', () {
    // Hindi and Marathi share a script, Urdu and Kashmiri too; the others must differ from each other.
    final bad = <String>[];
    for (final e in data.entries) {
      final en = e.value[AppLanguage.english] ?? '';
      if (_plain(en).runes.where(_isLetter).length < 12 || _sameOnPurpose.contains(e.key)) continue;
      for (final l in _scripts.keys) {
        if ((e.value[l] ?? '') == en) bad.add('${e.key}/${l.name}');
      }
    }
    expect(bad, isEmpty);
  });
}
