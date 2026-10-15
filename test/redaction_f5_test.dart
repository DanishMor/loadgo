import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/services/breadcrumbs.dart';
import 'package:transport_app/core/services/crash_service.dart';

/// F5: logs and crash reports carry no OTP, phone, UPI, bank or other personal data.
void main() {
  const samples = {
    'upi://pay?pa=ramesh@okbank&pn=Ramesh&am=500': 'ramesh',
    'pay to ramesh.k@ybl please': 'ramesh.k',
    'IFSC HDFC0001234 branch': 'HDFC0001234',
    'account 123456789012 failed': '123456789012',
    'acct no 1234 5678 9012 3456': '5678',
    'code is 482913 for you': '482913',
    'verification 771204 sent': '771204',
    'pincode 400001 invalid': '400001',
    'jwt eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJ4In0.c2ln bad': 'eyJhbGci',
    'token dQw4w9WgXcQ:APA91bHunMNqRsTuVwXyZaBcDeFgHiJk fail': 'APA91b',
    'verificationId AMkJ_x1y2z3-abcdefghijklmnopqrstuvwxyz0123456789ABCDEF lost': 'abcdefghijklmnop',
    'phone +91-98765-43210 and 9876543210': '98765',
    'upi id 9876543210@paytm': '9876543210',
  };

  test('each new kind of personal data is removed', () {
    samples.forEach((text, secret) {
      final out = Redactor.clean(text);
      expect(out.contains(secret), isFalse, reason: '"$text" -> "$out"');
    });
  });

  test('ordinary error text stays readable', () {
    for (final t in [
      'Bad state: no element',
      'type String is not a subtype of int',
      'permission-denied: Missing or insufficient permissions.',
      'index 12 out of range 0..11',
      'Failed host lookup',
    ]) {
      expect(Redactor.clean(t), t);
    }
  });

  test('safe() cleans any object and respects the length', () {
    expect(Redactor.safe(Exception('call 9876543210 back')), isNot(contains('9876543210')));
    expect(Redactor.safe('x' * 900).length, lessThanOrEqualTo(500));
    expect(Redactor.safe(null), 'null');
  });

  test('the error that goes to the crash report has a cleaned text and keeps the type', () {
    final e = RedactedError(StateError('otp 482913 rejected for asha@okbank, 9876543210'));
    expect(e.toString(), startsWith('StateError: '));
    for (final s in ['482913', 'asha', '9876543210']) {
      expect(e.toString().contains(s), isFalse, reason: e.toString());
    }
  });

  group('guards: the code does not print raw error or personal text', () {
    final files = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')).toList();

    test('every debugPrint that prints a value cleans it with Redactor', () {
      final bad = <String>[];
      for (final f in files) {
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final l = lines[i];
          if (l.contains('debugPrint(') && l.contains(r'$') && !l.contains('Redactor.')) bad.add('${f.path}:${i + 1}');
        }
      }
      expect(bad, isEmpty, reason: 'wrap the value in Redactor.safe(...)');
    });

    test('nobody calls print()', () {
      final bad = <String>[];
      for (final f in files) {
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (RegExp(r'(^|[^\w.])print\(').hasMatch(lines[i])) bad.add('${f.path}:${i + 1}');
        }
      }
      expect(bad, isEmpty);
    });

    test('Crashlytics gets only the cleaned error and no user identifier', () {
      final all = files.map((f) => f.readAsStringSync()).join('\n');
      expect(all.contains('setUserIdentifier'), isFalse);
      expect(all.contains('recordError(error'), isFalse);
      expect(File('lib/core/services/crash_service.dart').readAsStringSync(), contains('RedactedError(error)'));
    });
  });
}
