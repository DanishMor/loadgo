import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Z7: a button must never answer with a bare "Coming soon" toast. Anything that is not ready is hidden or disabled with its reason
/// (a flag that is OFF, or "Admin ne band rakha hai"). A "coming soon" text is allowed only next to a feature flag check.
void main() {
  test('no "Coming soon" toast without a feature-flag reason next to it', () {
    final bad = <String>[];
    final soon = RegExp(r"comingSoon|coming soon|Coming Soon|coming_soon");
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final p = f.path.replaceAll(r'\', '/');
      if (!p.endsWith('.dart') || p.contains('/l10n/')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!soon.hasMatch(lines[i])) continue;
        final near = lines.sublist((i - 8).clamp(0, lines.length), (i + 9).clamp(0, lines.length)).join('\n');
        if (!RegExp(r'FeatureKey\.|isOn\(|FeatureGate|FeaturesService').hasMatch(near)) bad.add('$p:${i + 1}');
      }
    }
    expect(bad, isEmpty, reason: 'Coming-soon text with no flag reason: $bad');
  });

  test('the driver and pending screens no longer use the Coming soon string', () {
    expect(File('lib/auth/driver_pending_screen.dart').readAsStringSync(), isNot(contains('comingSoon')));
    expect(File('lib/driver/driver_home_screen.dart').readAsStringSync(), isNot(contains('comingSoon')));
  });

  test('docs/SCREEN_INVENTORY.md is up to date with tool/screen_inventory.js', () {
    final before = File('docs/SCREEN_INVENTORY.md').readAsStringSync().replaceAll('\r\n', '\n');
    final r = Process.runSync('node', ['tool/screen_inventory.js', '--write']);
    expect(r.exitCode, 0);
    final after = File('docs/SCREEN_INVENTORY.md').readAsStringSync().replaceAll('\r\n', '\n');
    expect(after, before, reason: 'run: node tool/screen_inventory.js --write and commit docs/SCREEN_INVENTORY.md');
  });
}
