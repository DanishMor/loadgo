import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/services/breadcrumbs.dart';

/// Part 5 (H15): what a crash report or an error log line may never carry. Each text is a thing a stack
/// trace or an exception message can really contain.
void main() {
  String clean(String s) => Redactor.safe(s);

  group('secrets and keys never reach a log', () {
    const cases = {
      'payment key': 'Razorpay failed for key rzp_live_AbCdEfGhIjKlMn',
      'test key': 'key=rzp_test_AbCdEfGhIjKlMnOp',
      'google key': 'request to maps with key AIzaSyA1234567890abcdefghijklmnopqrstuvw failed',
      'bearer header': 'HTTP 401 Authorization: Bearer abcDEF123ghiJKL456',
      'github token': 'push rejected ghp_abcdefghijklmnopqrstuvwxyz0123456789',
      'jwt': 'token eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abc123def failed',
      'private key header': '-----BEGIN PRIVATE KEY----- MIIEvQIBADANBgkqhkiG9w0BAQEFAASC',
    };
    for (final e in cases.entries) {
      test(e.key, () {
        final out = clean(e.value);
        for (final secret in ['rzp_live_AbCdEfGhIjKlMn', 'rzp_test_AbCdEfGhIjKlMnOp', 'AIzaSyA1234567890abcdefghijklmnopqrstuvw', 'abcDEF123ghiJKL456', 'ghp_abcdefghijklmnopqrstuvwxyz0123456789', 'eyJhbGciOiJSUzI1NiJ9', 'MIIEvQIBADANBgkqhkiG9w0BAQEFAASC']) {
          expect(out.contains(secret), isFalse, reason: '${e.key}: "$out"');
        }
      });
    }
  });

  group('personal data never reaches a log', () {
    const cases = {
      'phone with +91': 'call failed for +91 98765 43210',
      'phone plain': 'sms to 9876543210 bounced',
      'aadhaar': 'kyc 1234 5678 9012 mismatch',
      'aadhaar without spaces': 'aadhaar 123456789012 invalid',
      'pan': 'pan ABCDE1234F rejected',
      'gstin': 'gst 27ABCDE1234F1Z5 not found',
      'vehicle number': 'vehicle MH12AB1234 busy',
      'trip code': 'wrong code 654321',
      'email': 'mail to asha.k@example.com failed',
      'upi id': 'pay asha@okhdfc',
      'upi link': 'launch upi://pay?pa=asha@okhdfc&am=500',
      'exact position': 'position 28.613939, 77.209021',
      'ifsc': 'ifsc HDFC0001234',
    };
    const secrets = ['98765 43210', '9876543210', '1234 5678 9012', '123456789012', 'ABCDE1234F', '27ABCDE1234F1Z5', 'MH12AB1234', '654321', 'asha.k@example.com', 'asha@okhdfc', '28.613939', '77.209021', 'HDFC0001234'];
    for (final e in cases.entries) {
      test(e.key, () {
        final out = clean(e.value);
        for (final s in secrets) {
          expect(out.contains(s), isFalse, reason: '${e.key}: "$out" still holds $s');
        }
      });
    }
  });

  test('hostile text: huge, control characters, nested JSON, none of it throws; the result is one short line', () {
    final inputs = <String>['x' * 200000, '\u0000\u0001\u0007 phone 9876543210', '{"a":{"b":{"phone":"+919876543210","otp":"123456"}}}', '\n\n\r\n', '', ' ' * 5000, List.filled(2000, '9876543210').join(',')];
    final clock = Stopwatch()..start();
    for (final t in inputs) {
      final out = Redactor.clean(t, maxLength: 300);
      expect(out.length, lessThanOrEqualTo(300));
      expect(out.contains('\n'), isFalse);
      expect(out.contains('9876543210'), isFalse);
    }
    expect(clock.elapsedMilliseconds, lessThan(3000), reason: 'logging an error must never freeze the app (it took minutes on a 200 000 letter text before the cut)');
  });

  test('ordinary words and short numbers stay readable (the log must still help)', () {
    expect(clean('Bad state: no booking found, retry 3 of 5'), 'Bad state: no booking found, retry 3 of 5');
  });
}
