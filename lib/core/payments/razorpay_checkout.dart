import 'dart:async';

import 'package:razorpay_flutter/razorpay_flutter.dart';

import 'online_pay.dart';

/// The Razorpay checkout window through the `razorpay_flutter` plugin. The key id
/// is the public one the server sent with the order; the secret never reaches the
/// phone. Needs a real phone to try (docs/KNOWN_ISSUES.md).
class RazorpayCheckout implements CheckoutLauncher {
  @override
  Future<CheckoutOutcome> open({required String keyId, required String orderId, required int amountPaise, required String description}) {
    final done = Completer<CheckoutOutcome>();
    final rzp = Razorpay();
    void finish(CheckoutOutcome o) {
      if (!done.isCompleted) done.complete(o);
      rzp.clear();
    }

    rzp.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
      final p = r.paymentId, s = r.signature;
      finish(p != null && s != null ? CheckoutOutcome.paid(p, s) : const CheckoutOutcome.cancelled());
    });
    rzp.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) => finish(const CheckoutOutcome.cancelled()));
    rzp.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) => finish(const CheckoutOutcome.cancelled()));
    try {
      rzp.open({
        'key': keyId,
        'order_id': orderId,
        'amount': amountPaise, // paise, the same as the server's order
        'name': 'Load 20',
        'description': description,
        'currency': 'INR',
        'theme': {'color': '#1B2A49'},
      });
    } catch (_) {
      finish(const CheckoutOutcome.cancelled());
    }
    return done.future;
  }
}
