import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/app_info.dart';

/// F39: the logo brief has the name, tagline, deliverables and the rights step.
void main() {
  final doc = File('docs/LOGO_BRIEF.md').readAsStringSync();

  test('the brief carries the real name and tagline', () {
    expect(doc, contains(AppInfo.name));
    expect(doc, contains('Maal bhejo, bharosa ke saath'));
    expect(doc, isNot(contains('LoadGo')));
  });

  test('it lists what to deliver, what to avoid and the rights', () {
    for (final s in ['512x512', '1024x500', 'adaptive icon', 'SVG', 'Kya na karein', 'assignment', 'trademark']) {
      expect(doc.toLowerCase(), contains(s.toLowerCase()), reason: s);
    }
    for (final f in ['docs/BRAND.md', 'docs/ICON_AND_SPLASH.md', 'docs/LEGAL_QUESTIONS.md', 'docs/NAME_CHECKLIST.md']) {
      expect(doc, contains(f));
      expect(File(f).existsSync(), isTrue, reason: f);
    }
  });
}
