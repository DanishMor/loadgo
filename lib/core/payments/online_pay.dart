import '../adapters/payment_adapter.dart';
import '../adapters/razorpay_gateway.dart';
import '../features/features.dart';
import '../models/booking.dart';
import '../services/features_service.dart';
import 'razorpay_checkout.dart';

/// What the checkout window answered.
class CheckoutOutcome {
  final String? paymentId;
  final String? signature;
  final bool cancelled;
  const CheckoutOutcome.paid(String this.paymentId, String this.signature) : cancelled = false;
  const CheckoutOutcome.cancelled()
      : paymentId = null,
        signature = null,
        cancelled = true;
}

/// Opens the payment partner's window for one order. The real one is
/// [RazorpayCheckout]; tests use a fake.
abstract class CheckoutLauncher {
  Future<CheckoutOutcome> open({required String keyId, required String orderId, required int amountPaise, required String description});
}

enum OnlinePayStatus { paid, cancelled, unavailable, failed }

class OnlinePayResult {
  final OnlinePayStatus status;
  final PaymentFailure? failure;
  const OnlinePayResult(this.status, [this.failure]);
}

/// G9: pay a booking online. Every step that matters happens on the server: it
/// makes the order from the booking's own amount, checks the signature and writes
/// the books. Here we only open the window and ask the server to check.
/// Behind the `paymentGateway` switch (OFF); with it off, or with no server, the
/// old "mark as paid" record flow is all the person sees.
class OnlinePay {
  OnlinePay._();

  static PaymentGateway gateway = RazorpayGateway();
  static CheckoutLauncher launcher = RazorpayCheckout();

  static bool get available => FeaturesService.isOn(FeatureKey.paymentGateway);

  static Future<OnlinePayResult> payBooking(Booking b) async {
    if (!available) return const OnlinePayResult(OnlinePayStatus.unavailable);
    final amount = b.billAmountPaise;
    if (amount == null || amount <= 0) return const OnlinePayResult(OnlinePayStatus.failed, PaymentFailure.invalidAmount);
    final (order, why) = await gateway.createOrder(amount, b.id);
    if (order == null) {
      return OnlinePayResult(why == PaymentFailure.notConfigured ? OnlinePayStatus.unavailable : OnlinePayStatus.failed, why);
    }
    final keyId = order.keyId;
    if (keyId == null) return const OnlinePayResult(OnlinePayStatus.unavailable, PaymentFailure.notConfigured);
    CheckoutOutcome outcome;
    try {
      outcome = await launcher.open(keyId: keyId, orderId: order.id, amountPaise: order.amountPaise, description: b.id);
    } catch (_) {
      return const OnlinePayResult(OnlinePayStatus.failed);
    }
    if (outcome.cancelled || outcome.paymentId == null || outcome.signature == null) return const OnlinePayResult(OnlinePayStatus.cancelled);
    final r = await gateway.verify(order.id, outcome.paymentId!, outcome.signature!);
    return r.ok ? const OnlinePayResult(OnlinePayStatus.paid) : OnlinePayResult(OnlinePayStatus.failed, r.failure);
  }
}
