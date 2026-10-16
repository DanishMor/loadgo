import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/features/features.dart';

/// F36/F37: the go-live list names every switch the server side uses, in order, and has no secret.
void main() {
  final doc = File('docs/BLAZE_GO_LIVE.md').readAsStringSync();

  test('every server-side switch has a row in the switch-on table', () {
    final server = Features.registry.map((s) => s.key).where((k) => k.startsWith('server') || const ['pushNotifications', 'adminBroadcast', 'photoUploads', 'paymentGateway'].contains(k));
    expect(server, isNotEmpty);
    for (final k in server) {
      expect(doc, contains('| `$k` |'), reason: k);
    }
  });

  test('the first steps are in the safe order', () {
    final order = ['## 1. Take the Blaze plan', '## 2. Rules and indexes', '## 3. Turn Storage on', '## 4. Functions', '## 5. Switch on', '## 8. Online payment', '## 9. Live keys'];
    var last = -1;
    for (final h in order) {
      final i = doc.indexOf(h);
      expect(i, greaterThan(last), reason: h);
      last = i;
    }
    expect(doc.indexOf('budget'), lessThan(doc.indexOf('firebase deploy --only functions')));
  });

  test('no real key is written in the docs; secrets are typed by the owner', () {
    expect(RegExp(r'rzp_(test|live)_[A-Za-z0-9]{6,}').hasMatch(doc), isFalse);
    expect(doc, contains('firebase functions:secrets:set RAZORPAY_KEY_SECRET'));
    expect(doc, contains('Claude never runs a deploy'));
  });

  test('the paid plan names the new adapters and the files exist', () {
    final plan = File('docs/PAID_UPGRADE_PLAN.md').readAsStringSync();
    for (final f in ['lib/core/adapters/razorpay_gateway.dart', 'functions/src/razorpay.js', 'lib/core/adapters/partner_adapters.dart']) {
      expect(plan, contains(f));
      expect(File(f).existsSync(), isTrue, reason: f);
    }
  });
}
