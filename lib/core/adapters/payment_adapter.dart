class PaymentOrder {
  final String id;

  /// Integer paise, always.
  final int amountPaise;
  final String reference; // booking id
  const PaymentOrder(this.id, this.amountPaise, this.reference);
}

enum PaymentFailure { notConfigured, invalidAmount, unknownOrder, badSignature, alreadyRefunded, refundTooLarge }

class PaymentResult {
  final bool ok;
  final PaymentFailure? failure;
  const PaymentResult.ok()
      : ok = true,
        failure = null;
  const PaymentResult.failed(PaymentFailure this.failure) : ok = false;
}

/// LATER(paid): a payment gateway (UPI / card). The money flow, escrow-like
/// hold and driver payouts stay "record only" until this is plugged in and
/// Cloud Functions verify signatures on the server (TODO(functions)).
abstract class PaymentGateway {
  /// [amountPaise] must be a positive whole number of paise, at most 1 crore rupees.
  Future<(PaymentOrder?, PaymentFailure?)> createOrder(int amountPaise, String reference);

  /// Checks the gateway's callback signature for [orderId].
  Future<PaymentResult> verify(String orderId, String paymentId, String signature);

  /// Refund up to what was paid, in total.
  Future<PaymentResult> refund(String paymentId, int amountPaise);
}

const maxOrderPaise = 100 * 1000 * 1000 * 100; // 1 crore rupees

class NoPaymentGateway implements PaymentGateway {
  const NoPaymentGateway();
  @override
  Future<(PaymentOrder?, PaymentFailure?)> createOrder(int amountPaise, String reference) async => (null, PaymentFailure.notConfigured);
  @override
  Future<PaymentResult> verify(String orderId, String paymentId, String signature) async => const PaymentResult.failed(PaymentFailure.notConfigured);
  @override
  Future<PaymentResult> refund(String paymentId, int amountPaise) async => const PaymentResult.failed(PaymentFailure.notConfigured);
}

class FakePaymentGateway implements PaymentGateway {
  final Map<String, PaymentOrder> _orders = {};
  final Map<String, String> _paymentOrder = {};
  final Map<String, int> _refunded = {};
  int _n = 0;

  /// What the fake accepts as a good signature for (order, payment).
  static String signatureFor(String orderId, String paymentId) => 'sig:$orderId:$paymentId';

  @override
  Future<(PaymentOrder?, PaymentFailure?)> createOrder(int amountPaise, String reference) async {
    if (amountPaise <= 0 || amountPaise > maxOrderPaise) return (null, PaymentFailure.invalidAmount);
    final o = PaymentOrder('o${++_n}', amountPaise, reference);
    _orders[o.id] = o;
    return (o, null);
  }

  @override
  Future<PaymentResult> verify(String orderId, String paymentId, String signature) async {
    if (!_orders.containsKey(orderId)) return const PaymentResult.failed(PaymentFailure.unknownOrder);
    if (signature != signatureFor(orderId, paymentId)) return const PaymentResult.failed(PaymentFailure.badSignature);
    _paymentOrder[paymentId] = orderId;
    return const PaymentResult.ok();
  }

  @override
  Future<PaymentResult> refund(String paymentId, int amountPaise) async {
    final order = _orders[_paymentOrder[paymentId]];
    if (order == null) return const PaymentResult.failed(PaymentFailure.unknownOrder);
    if (amountPaise <= 0) return const PaymentResult.failed(PaymentFailure.invalidAmount);
    final already = _refunded[paymentId] ?? 0;
    if (already >= order.amountPaise) return const PaymentResult.failed(PaymentFailure.alreadyRefunded);
    if (already + amountPaise > order.amountPaise) return const PaymentResult.failed(PaymentFailure.refundTooLarge);
    _refunded[paymentId] = already + amountPaise;
    return const PaymentResult.ok();
  }
}
