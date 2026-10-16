import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// G17: every server call that costs money has a switch, a daily limit per person and in total, and is named in
/// COST_WATCH.md with the config document that sets the limit. A new paid call must be added here on purpose.
void main() {
  final index = File('functions/index.js').readAsStringSync();
  final cost = File('docs/COST_WATCH.md').readAsStringSync();

  // (function name, switch, source file that must call the quota, config document named in the cost notes)
  const paid = <(String, String, String, String)>[
    ('paymentCreateOrder', 'paymentGateway', 'functions/src/razorpay.js', 'config/paymentLimits'),
    ('mapsRoute', 'maps', 'functions/src/maps.js', 'config/mapsLimits'),
    ('smsSend', 'smsGateway', 'functions/src/sms.js', 'config/sms'),
    ('kycVerify', 'kycVerify', 'functions/src/kyc.js', 'config/kyc'),
  ];

  for (final (fn, flag, file, cfg) in paid) {
    test('$fn: switch "$flag", a quota in $file and the limits in $cfg are written down', () {
      expect(index, contains('exports.$fn'));
      expect(index, contains("flagOn(db, '$flag')"));
      final src = File(file).readAsStringSync();
      expect(src.contains('consume(') || src.contains('consumeQuota('), isTrue, reason: '$file has no daily quota');
      expect(cost, contains(cfg), reason: '$cfg is not named in COST_WATCH.md');
    });
  }

  test('the SMS notification trigger and the webhook also sit behind their switch', () {
    expect(RegExp(r"exports\.smsOnNotification[\s\S]{0,400}flagOn\(db, 'smsGateway'\)").hasMatch(index), isTrue);
    expect(RegExp(r"exports\.paymentWebhook[\s\S]{0,600}flagOn\(db, 'paymentGateway'\)").hasMatch(index), isTrue);
  });

  test('every paid callable asks the App Check guard after its switch', () {
    for (final fn in ['mapsRoute', 'smsSend', 'kycVerify']) {
      expect(RegExp(r'exports\.' + fn + r'[\s\S]{0,500}appCheckGuard\(').hasMatch(index), isTrue, reason: fn);
    }
    expect(RegExp(r'paymentCallable[\s\S]{0,900}appCheckGuard\(').hasMatch(index), isTrue);
  });

  test('quota documents expire: the cost notes tell the owner to set a TTL policy', () {
    expect(cost, contains('TTL'));
  });

  test('limits are whole numbers read defensively (no negative or text limit turns the guard off)', () {
    final q = File('functions/src/quota.js').readAsStringSync();
    expect(q, contains('Number.isSafeInteger'));
  });
}
