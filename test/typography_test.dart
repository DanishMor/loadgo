import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/theme/design_tokens.dart';

/// L6: the brand font is bundled with its licence, registered, used by the
/// theme, and every letter of every language is in a bundled font (read from
/// the font files themselves, so a missing glyph shows up here, not as a box
/// on a phone).

/// The code points a TrueType font really draws (cmap formats 4 and 12).
Set<int> glyphsOf(File f) {
  final d = ByteData.sublistView(f.readAsBytesSync());
  final tables = d.getUint16(4);
  int cmapAt = -1;
  for (var i = 0; i < tables; i++) {
    final rec = 12 + i * 16;
    final tag = String.fromCharCodes([for (var k = 0; k < 4; k++) d.getUint8(rec + k)]);
    if (tag == 'cmap') cmapAt = d.getUint32(rec + 8);
  }
  if (cmapAt < 0) return {};
  final out = <int>{};
  final n = d.getUint16(cmapAt + 2);
  for (var i = 0; i < n; i++) {
    final rec = cmapAt + 4 + i * 8;
    final sub = cmapAt + d.getUint32(rec + 4);
    final format = d.getUint16(sub);
    if (format == 4) {
      final segX2 = d.getUint16(sub + 6);
      final seg = segX2 ~/ 2;
      final endAt = sub + 14;
      final startAt = endAt + segX2 + 2;
      final deltaAt = startAt + segX2;
      final rangeAt = deltaAt + segX2;
      for (var s = 0; s < seg; s++) {
        final end = d.getUint16(endAt + s * 2), start = d.getUint16(startAt + s * 2);
        final delta = d.getUint16(deltaAt + s * 2), range = d.getUint16(rangeAt + s * 2);
        for (var c = start; c <= end && c != 0xFFFF; c++) {
          int gid;
          if (range == 0) {
            gid = (c + delta) & 0xFFFF;
          } else {
            final at = rangeAt + s * 2 + range + (c - start) * 2;
            if (at + 2 > d.lengthInBytes) continue;
            final v = d.getUint16(at);
            gid = v == 0 ? 0 : (v + delta) & 0xFFFF;
          }
          if (gid != 0) out.add(c);
        }
      }
    } else if (format == 12) {
      final groups = d.getUint32(sub + 12);
      for (var g = 0; g < groups; g++) {
        final at = sub + 16 + g * 12;
        final start = d.getUint32(at), end = d.getUint32(at + 4);
        for (var c = start; c <= end; c++) {
          out.add(c);
        }
      }
    }
  }
  return out;
}

/// Characters that need no glyph from our fonts: spaces, controls, joiners and
/// direction marks, and symbols or emoji the phone draws from its own font.
bool needsNoFont(int c) =>
    c <= 0x20 || (c >= 0x7F && c <= 0xA0) || c == 0x200B || c == 0x200C || c == 0x200D || c == 0x200E || c == 0x200F || c == 0x202A || c == 0x202B || c == 0x202C || c == 0x2066 || c == 0x2067 || c == 0x2068 || c == 0x2069 || c == 0xFEFF || c == 0xFE0F || (c >= 0x2190 && c <= 0x2BFF) || c >= 0x1F000;

void main() {
  File mukta(String n) => File('assets/fonts/mukta/$n');
  const noto = {
    'NotoSans': 'NotoSans-Regular.ttf',
    'NotoSansKannada': 'NotoSansKannada-Regular.ttf',
    'NotoSansTamil': 'NotoSansTamil-Regular.ttf',
    'NotoSansTelugu': 'NotoSansTelugu-Regular.ttf',
    'NotoSansGujarati': 'NotoSansGujarati-Regular.ttf',
    'NotoSansBengali': 'NotoSansBengali-Regular.ttf',
    'NotoSansGurmukhi': 'NotoSansGurmukhi-Regular.ttf',
    'NotoNaskhArabic': 'NotoNaskhArabic-Regular.ttf',
  };
  final pubspec = File('pubspec.yaml').readAsStringSync();

  test('Mukta is bundled in three weights with its SIL OFL licence', () {
    for (final n in ['Mukta-Regular.ttf', 'Mukta-SemiBold.ttf', 'Mukta-Bold.ttf']) {
      final f = mukta(n);
      expect(f.existsSync(), isTrue, reason: n);
      final head = f.readAsBytesSync().sublist(0, 4);
      expect(head, [0, 1, 0, 0], reason: '$n is a TrueType file');
    }
    final lic = mukta('OFL.txt').readAsStringSync();
    expect(lic, contains('SIL OPEN FONT LICENSE'));
    expect(lic, contains('Copyright'));
  });

  test('pubspec registers Mukta (400, 600, 700) and every fallback family', () {
    expect(pubspec, contains('family: Mukta'));
    expect(pubspec, contains('Mukta-SemiBold.ttf'));
    expect(pubspec, contains('weight: 600'));
    expect(pubspec, contains('weight: 700'));
    expect(pubspec, contains('- assets/fonts/mukta/'));
    for (final fam in noto.keys) {
      expect(pubspec, contains('family: $fam'), reason: fam);
    }
    for (final f in noto.values) {
      expect(File('assets/fonts/$f').existsSync(), isTrue, reason: f);
    }
  });

  test('the type scale and the theme use Mukta with the fallback chain', () {
    expect(DsType.family, 'Mukta');
    expect(DsType.fallback.toSet().containsAll(noto.keys), isTrue);
    expect(DsType.body.fontFamily, 'Mukta');
    expect(DsType.body.fontFamilyFallback, DsType.fallback);
    final t = AppTheme.build(Brightness.light);
    expect(t.textTheme.bodyLarge!.fontFamily, 'Mukta');
    expect(t.textTheme.bodyLarge!.fontFamilyFallback, DsType.fallback);
  });

  test('Mukta draws Latin, digits, the rupee sign and Devanagari', () {
    final g = glyphsOf(mukta('Mukta-Regular.ttf'));
    for (final c in 'AZaz09'.runes) {
      expect(g.contains(c), isTrue, reason: String.fromCharCode(c));
    }
    expect(g.contains(0x20B9), isTrue, reason: 'rupee sign');
    for (final c in 'नमस्ते लोड'.runes.where((c) => c != 0x20)) {
      expect(g.contains(c), isTrue, reason: 'U+${c.toRadixString(16)}');
    }
  });

  // Which bundled fonts serve each language.
  final chain = <AppLanguage, List<String>>{
    AppLanguage.english: ['NotoSans'],
    AppLanguage.hindi: ['NotoSans'],
    AppLanguage.hinglish: ['NotoSans'],
    AppLanguage.marathi: ['NotoSans'],
    AppLanguage.kannada: ['NotoSans', 'NotoSansKannada'],
    AppLanguage.tamil: ['NotoSans', 'NotoSansTamil'],
    AppLanguage.telugu: ['NotoSans', 'NotoSansTelugu'],
    AppLanguage.gujarati: ['NotoSans', 'NotoSansGujarati'],
    AppLanguage.bengali: ['NotoSans', 'NotoSansBengali'],
    AppLanguage.punjabi: ['NotoSans', 'NotoSansGurmukhi'],
    AppLanguage.kashmiri: ['NotoSans', 'NotoNaskhArabic'],
    AppLanguage.urdu: ['NotoSans', 'NotoNaskhArabic'],
  };

  test('every language has a font chain', () {
    expect(chain.keys.toSet(), AppLanguage.values.toSet());
  });

  for (final lang in AppLanguage.values) {
    test('${lang.name}: every letter of every string is in Mukta or the bundled fonts', () {
      final have = <int>{...glyphsOf(mukta('Mukta-Regular.ttf'))};
      for (final fam in chain[lang]!) {
        have.addAll(glyphsOf(File('assets/fonts/${noto[fam]}')));
      }
      final missing = <int, String>{};
      for (final e in T.data.entries) {
        final s = e.value[lang];
        if (s == null) continue;
        for (final c in s.runes) {
          if (needsNoFont(c) || have.contains(c)) continue;
          missing.putIfAbsent(c, () => e.key);
        }
      }
      final shown = missing.entries.take(12).map((m) => 'U+${m.key.toRadixString(16).toUpperCase()} (${String.fromCharCode(m.key)}) in ${m.value}').toList();
      expect(missing, isEmpty, reason: '${missing.length} code point(s) without a glyph: $shown');
    });
  }

  testWidgets('Hindi, Urdu and Tamil text lays out in the theme without a throw at 2.0x', (t) async {
    for (final txt in ['लोड 20: माल भेजो, भरोसे के साथ', 'لوڈ 20: مال بھیجیں', 'லோட் 20: சரக்கை அனுப்புங்கள்']) {
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.build(Brightness.light),
        builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(2.0)), child: child!),
        home: Scaffold(body: Directionality(textDirection: txt.startsWith('ل') ? TextDirection.rtl : TextDirection.ltr, child: SizedBox(width: 200, child: Text(txt)))),
      ));
      expect(t.takeException(), isNull, reason: txt);
    }
  });
}
