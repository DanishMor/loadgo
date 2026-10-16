import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/adapters/adapters.dart';
import 'package:transport_app/core/services/server_actions.dart';

/// A stand-in for the Cloud Functions with the same rules as functions/src/razorpay.js:
/// the amount is the booking's own, the signature must match, refunds add up to what was paid.
class FakeRazorpayServer implements ServerGateway {
  final Map<String, int> bookings;
  final Map<String, int> orderAmount = {};
  final Map<String, String> orderOfPayment = {};
  final Map<String, int> refunded = {};
  final calls = <String>[];
  Object? down;
  int _n = 0;

  FakeRazorpayServer(this.bookings);

  FirebaseFunctionsException err(String code, [String message = '']) => FirebaseFunctionsException(code: code, message: message);

  @override
  Future<Map<String, dynamic>> call(String name, Map<String, Object?> data) async {
    calls.add(name);
    if (down != null) throw down!;
    switch (name) {
      case 'paymentCreateOrder':
        final amount = bookings[data['bookingId']];
        if (amount == null) throw err('not-found', 'booking');
        final id = 'order_${++_n}';
        orderAmount[id] = amount;
        return {'orderId': id, 'amountPaise': amount, 'reference': data['bookingId']};
      case 'paymentVerify':
        final o = data['orderId'];
        if (!orderAmount.containsKey(o)) throw err('not-found', 'order');
        if (data['signature'] != FakePaymentGateway.signatureFor('$o', '${data['paymentId']}')) throw err('permission-denied', 'bad signature');
        orderOfPayment['${data['paymentId']}'] = '$o';
        return {'ok': true};
      case 'paymentRefund':
        final o = data['orderId'] as String;
        final amount = orderAmount[o]!;
        final already = refunded[o] ?? 0;
        if (already >= amount) throw err('failed-precondition', 'already refunded');
        if (already + (data['amountPaise'] as int) > amount) throw err('failed-precondition', 'more than was paid');
        refunded[o] = already + (data['amountPaise'] as int);
        return {'ok': true};
    }
    throw err('not-found');
  }
}

/// F34: the Razorpay adapter meets the same promises as the fake gateway.
void main() {
  late FakeRazorpayServer server;
  late RazorpayGateway g;
  setUp(() {
    server = FakeRazorpayServer({'B1': 250000});
    g = RazorpayGateway(server);
  });

  test('whole positive paise only; the order carries the booking and its amount', () async {
    for (final bad in [0, -5, maxOrderPaise + 1]) {
      expect((await g.createOrder(bad, 'B1')).$2, PaymentFailure.invalidAmount, reason: '$bad');
    }
    expect(server.calls, isEmpty, reason: 'bad amounts never reach the server');
    final ok = await g.createOrder(250000, 'B1');
    expect(ok.$1!.amountPaise, 250000);
    expect(ok.$1!.reference, 'B1');
  });

  test('an amount that is not the booking amount is refused, and an unknown booking is unknownOrder', () async {
    expect((await g.createOrder(1, 'B1')).$2, PaymentFailure.invalidAmount);
    expect((await g.createOrder(100, 'NOPE')).$2, PaymentFailure.unknownOrder);
  });

  test('a forged signature or unknown order is refused; a good one passes', () async {
    final o = (await g.createOrder(250000, 'B1')).$1!;
    expect((await g.verify(o.id, 'p1', 'forged')).failure, PaymentFailure.badSignature);
    expect((await g.verify('nope', 'p1', 'x')).failure, PaymentFailure.unknownOrder);
    expect((await g.verify(o.id, 'p1', FakePaymentGateway.signatureFor(o.id, 'p1'))).ok, isTrue);
  });

  test('refunds add up to at most what was paid', () async {
    final o = (await g.createOrder(250000, 'B1')).$1!;
    await g.verify(o.id, 'p1', FakePaymentGateway.signatureFor(o.id, 'p1'));
    expect((await g.refund('p1', 100000)).ok, isTrue);
    expect((await g.refund('p1', 200000)).failure, PaymentFailure.refundTooLarge);
    expect((await g.refund('p1', 150000)).ok, isTrue);
    expect((await g.refund('p1', 1)).failure, PaymentFailure.alreadyRefunded);
    expect((await g.refund('p1', 0)).failure, PaymentFailure.invalidAmount);
    expect((await g.refund('unknown', 100)).failure, PaymentFailure.unknownOrder);
  });

  test('server off, not deployed or offline is notConfigured, never an exception', () async {
    server.down = FirebaseFunctionsException(code: 'failed-precondition', message: 'disabled');
    expect((await g.createOrder(250000, 'B1')).$2, PaymentFailure.notConfigured);
    server.down = Exception('offline');
    expect((await g.createOrder(250000, 'B1')).$2, PaymentFailure.notConfigured);
    expect((await g.verify('o', 'p', 's')).failure, PaymentFailure.notConfigured);
  });

  test('no Razorpay key or secret is in the app or the repository files', () {
    final pattern = RegExp(r'rzp_(test|live)_[A-Za-z0-9]{6,}');
    for (final root in ['lib', 'functions/src', 'functions/index.js', 'docs']) {
      final entity = FileSystemEntity.typeSync(root) == FileSystemEntityType.directory ? Directory(root).listSync(recursive: true).whereType<File>() : [File(root)];
      for (final f in entity) {
        if (f.path.contains('node_modules')) continue;
        expect(pattern.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
      }
    }
  });
}
