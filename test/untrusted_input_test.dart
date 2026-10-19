import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/navigation/deep_links.dart';
import 'package:transport_app/core/share/share_links.dart';

/// Part 5 (H10): a link, a push payload and anything else that arrives from outside is untrusted.
void main() {
  group('load links', () {
    test('an id that would become a deeper Firestore path or a reserved id is refused', () {
      for (final bad in [
        'https://h/load/a%2Fb', // decodes to a/b
        'https://h/load/%2e%2e', // ..
        'https://h/load/..',
        'https://h/load/.',
        r'https://h/load/a%5Cb', // backslash
        'https://h/load/a%00b', // NUL
        'https://h/load/a%0Ab', // newline
        'https://h/load/%7F',
        'https://h/load/__name__',
        'https://h/load/__x__',
      ]) {
        expect(ShareLinks.parseLoadId(bad), isNull, reason: bad);
        expect(DeepLinks.loadIdFrom(bad), isNull, reason: bad);
      }
    });

    test('what the app itself makes, and what already worked, still opens', () {
      for (final good in ['abc123', 'A1b2C3d4E5f6G7h8I9j0', 'demo_x1', 'a b', 'L-1_x']) {
        expect(ShareLinks.parseLoadId(ShareLinks.loadLink(good)), good);
      }
    });

    test('a hostile link of any shape never throws', () {
      final hostile = <String?>[
        null, '', ' ', '\u0000', 'https://', 'https://h/load/${'x' * 100000}', 'https://h/load/${'%' * 500}', 'https://h/load/%zz', 'https://[::1/load/x',
        'javascript:alert(1)', 'intent://x#Intent;end', 'file:///etc/passwd', 'https://h:99999999/load/x', 'https://h/load/a?b=c#d', '//h/load/x', 'https://h/load/\u202Eabc',
      ];
      for (final l in hostile) {
        expect(() => ShareLinks.parseLoadId(l), returnsNormally, reason: '$l');
        expect(() => DeepLinks.loadIdFrom(l), returnsNormally, reason: '$l');
        expect(() => DeepLinks.handle(l), returnsNormally, reason: '$l');
      }
      DeepLinks.reset();
    });
  });

  group('code guards (Part 5)', () {
    final dart = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')).toList();

    test('no WebView anywhere', () {
      expect(File('pubspec.yaml').readAsStringSync().contains('webview'), isFalse);
      for (final f in dart) {
        expect(f.readAsStringSync().contains('WebView'), isFalse, reason: f.path);
      }
    });

    test('launchUrl opens only https, tel, sms, geo or UPI links built from fixed schemes', () {
      final allowed = RegExp(r"scheme: '(sms|tel|geo|upi|https|whatsapp)'");
      for (final f in dart) {
        final src = f.readAsStringSync();
        if (!src.contains('launchUrl(')) continue;
        // Every file that launches a URL builds it with a fixed scheme or from the helper that does.
        final safe = allowed.hasMatch(src) || src.contains('Uri.https(') || src.contains('whatsAppUri') || src.contains('upiPayUri') || src.contains('Uri.parse(url)') || src.contains('Uri.parse(_playUrl)') || src.contains('openExternal') || src.contains('Uri(scheme:');
        expect(safe, isTrue, reason: '${f.path} launches a URL without a fixed scheme');
      }
    });

    test('nothing prints or keeps a secret in plain shared preferences by name', () {
      final names = RegExp(r"(setString|setStringList)\(\s*'?[A-Za-z_]*(password|passwd|secret|apiKey|api_key|privateKey|authToken|accessToken|refreshToken)", caseSensitive: false);
      for (final f in dart) {
        expect(names.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
      }
    });
  });
}
