import 'package:cloud_functions/cloud_functions.dart';

import '../services/server_actions.dart';
import 'payment_adapter.dart';

/// Razorpay (test mode first) behind [PaymentGateway] (F34).
///
/// The app never holds a Razorpay key. Every step is a call to a Cloud Function
/// (`paymentCreateOrder`, `paymentVerify`, `paymentRefund`) that holds the secret,
/// takes the amount from the booking and checks the signature. This class only
/// turns the answers into the typed results the rest of the app already uses, so
/// a missing or switched-off server is `notConfigured`, never a crash.
class RazorpayGateway implements PaymentGateway {
  final ServerGateway server;

  /// payment id -> order id, remembered from [verify] so a refund can name its order.
  final Map<String, String> _orderOfPayment = {};

  RazorpayGateway([ServerGateway? server]) : server = server ?? ServerActions.gateway;

  @override
  Future<(PaymentOrder?, PaymentFailure?)> createOrder(int amountPaise, String reference) async {
    if (amountPaise <= 0 || amountPaise > maxOrderPaise) return (null, PaymentFailure.invalidAmount);
    try {
      // Only the booking is sent. The server uses the booking's own amount and
      // answers with it; a different amount than asked is refused here.
      final r = await server.call('paymentCreateOrder', {'bookingId': reference});
      final id = r['orderId'];
      final paise = r['amountPaise'];
      if (id is! String || paise is! int || paise <= 0 || paise > maxOrderPaise) return (null, PaymentFailure.notConfigured);
      if (paise != amountPaise) return (null, PaymentFailure.invalidAmount);
      final key = r['keyId'];
      final okKey = key is String && RegExp(r'^[A-Za-z0-9_]{6,60}$').hasMatch(key);
      return (PaymentOrder(id, paise, reference, okKey ? key : null), null);
    } catch (e) {
      return (null, _failure(e, PaymentFailure.notConfigured));
    }
  }

  @override
  Future<PaymentResult> verify(String orderId, String paymentId, String signature) async {
    try {
      final r = await server.call('paymentVerify', {'orderId': orderId, 'paymentId': paymentId, 'signature': signature});
      if (r['ok'] != true) return const PaymentResult.failed(PaymentFailure.badSignature);
      _orderOfPayment[paymentId] = orderId;
      return const PaymentResult.ok();
    } catch (e) {
      return PaymentResult.failed(_failure(e, PaymentFailure.notConfigured));
    }
  }

  @override
  Future<PaymentResult> refund(String paymentId, int amountPaise) async {
    final order = _orderOfPayment[paymentId];
    if (order == null) return const PaymentResult.failed(PaymentFailure.unknownOrder);
    if (amountPaise <= 0 || amountPaise > maxOrderPaise) return const PaymentResult.failed(PaymentFailure.invalidAmount);
    try {
      final r = await server.call('paymentRefund', {'orderId': order, 'amountPaise': amountPaise});
      return r['ok'] == true ? const PaymentResult.ok() : const PaymentResult.failed(PaymentFailure.notConfigured);
    } catch (e) {
      return PaymentResult.failed(_failure(e, PaymentFailure.notConfigured));
    }
  }

  static PaymentFailure _failure(Object e, PaymentFailure otherwise) {
    if (e is! FirebaseFunctionsException) return otherwise;
    switch (e.code) {
      case 'not-found':
        return PaymentFailure.unknownOrder;
      case 'permission-denied':
        return PaymentFailure.badSignature;
      case 'invalid-argument':
        return PaymentFailure.invalidAmount;
      case 'failed-precondition':
        final m = e.message ?? '';
        if (m.contains('already refunded')) return PaymentFailure.alreadyRefunded;
        if (m.contains('more than was paid')) return PaymentFailure.refundTooLarge;
        return otherwise;
      default:
        return otherwise;
    }
  }
}
