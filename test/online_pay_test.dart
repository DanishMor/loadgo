import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/adapters/payment_adapter.dart';
import 'package:transport_app/core/documents/payment_card.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/payments/online_pay.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';


class _Gateway implements PaymentGateway {
  PaymentFailure? createFails;
  PaymentFailure? verifyFails;
  String? key = 'key_abc123';
  int? lastAmount;
  String? lastReference;
  int verifyCalls = 0;

  @override
  Future<(PaymentOrder?, PaymentFailure?)> createOrder(int amountPaise, String reference) async {
    lastAmount = amountPaise;
    lastReference = reference;
    if (createFails != null) return (null, createFails);
    return (PaymentOrder('order_1', amountPaise, reference, key), null);
  }

  @override
  Future<PaymentResult> verify(String orderId, String paymentId, String signature) async {
    verifyCalls++;
    return verifyFails == null ? const PaymentResult.ok() : PaymentResult.failed(verifyFails!);
  }

  @override
  Future<PaymentResult> refund(String paymentId, int amountPaise) async => const PaymentResult.failed(PaymentFailure.notConfigured);
}

class _Launcher implements CheckoutLauncher {
  CheckoutOutcome outcome = const CheckoutOutcome.paid('pay_1', 'sig');
  bool throws = false;
  Map<String, Object?>? last;

  @override
  Future<CheckoutOutcome> open({required String keyId, required String orderId, required int amountPaise, required String description}) async {
    last = {'keyId': keyId, 'orderId': orderId, 'amountPaise': amountPaise};
    if (throws) throw StateError('no window');
    return outcome;
  }
}

Booking _booking({String status = 'accepted', String payment = 'pending', int fare = 1800000}) => Booking.fromMap('b1', {
      'customerId': 'customer1', 'driverId': 'driver1', 'status': status, 'agreedFarePaise': fare, 'paymentStatus': payment,
      'pickup': 'Delhi', 'drop': 'Jaipur', 'loadId': 'l1', 'vehicleId': 'v1', 'cargoType': 'FMCG', 'weight': 2, 'vehicleType': '14ft',
      'notes': '', 'vehicleNumber': 'N', 'driverName': 'D', 'driverPhone': '1', 'timeline': <String, Object?>{},
    });

void main() {
  late _Gateway gw;
  late _Launcher launcher;

  setUp(() {
    gw = _Gateway();
    launcher = _Launcher();
    OnlinePay.gateway = gw;
    OnlinePay.launcher = launcher;
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.paymentGateway: true});
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'customer1');
    languageNotifier.value = AppLanguage.english;
  });
  tearDown(FeaturesService.reset);

  test('switch off: nothing is called', () async {
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.paymentGateway: false});
    final r = await OnlinePay.payBooking(_booking());
    expect(r.status, OnlinePayStatus.unavailable);
    expect(gw.lastAmount, isNull);
    expect(launcher.last, isNull);
  });

  test('a good payment: the order is for the bill amount, the window gets the server key, the server checks the signature', () async {
    final r = await OnlinePay.payBooking(_booking());
    expect(r.status, OnlinePayStatus.paid);
    expect(gw.lastAmount, 1800000);
    expect(gw.lastReference, 'b1');
    expect(launcher.last, {'keyId': 'key_abc123', 'orderId': 'order_1', 'amountPaise': 1800000});
    expect(gw.verifyCalls, 1);
  });

  test('cancelled window: nothing is verified', () async {
    launcher.outcome = const CheckoutOutcome.cancelled();
    final r = await OnlinePay.payBooking(_booking());
    expect(r.status, OnlinePayStatus.cancelled);
    expect(gw.verifyCalls, 0);
  });

  test('a window that fails to open, a server that is not there, a bad signature and no key are calm results', () async {
    launcher.throws = true;
    expect((await OnlinePay.payBooking(_booking())).status, OnlinePayStatus.failed);
    launcher.throws = false;
    gw.createFails = PaymentFailure.notConfigured;
    expect((await OnlinePay.payBooking(_booking())).status, OnlinePayStatus.unavailable);
    gw.createFails = PaymentFailure.invalidAmount;
    expect((await OnlinePay.payBooking(_booking())).status, OnlinePayStatus.failed);
    gw.createFails = null;
    gw.verifyFails = PaymentFailure.badSignature;
    final bad = await OnlinePay.payBooking(_booking());
    expect(bad.status, OnlinePayStatus.failed);
    expect(bad.failure, PaymentFailure.badSignature);
    gw.verifyFails = null;
    gw.key = null;
    expect((await OnlinePay.payBooking(_booking())).status, OnlinePayStatus.unavailable);
  });

  testWidgets('the card shows Pay online to the customer only, only while unpaid and only with the switch on', (tester) async {
    Future<void> show(Booking b) async => tester.pumpWidget(MaterialApp(home: Scaffold(body: PaymentCard(key: UniqueKey(), booking: b))));
    await show(_booking());
    expect(find.byKey(const ValueKey('payOnline')), findsOneWidget);
    expect(find.text('Pay online'), findsOneWidget);
    await show(_booking(payment: 'customer_marked_paid'));
    expect(find.byKey(const ValueKey('payOnline')), findsNothing);
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.paymentGateway: false});
    await show(_booking());
    expect(find.byKey(const ValueKey('payOnline')), findsNothing);
    expect(find.byKey(const ValueKey('markPaid')), findsOneWidget, reason: 'the old record flow is still there');
  });

  testWidgets('tapping Pay online shows the done message', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PaymentCard(booking: _booking()))));
    await tester.tap(find.byKey(const ValueKey('payOnline')));
    await tester.pumpAndSettle();
    expect(find.text('Payment received. The driver is paid when the trip is done.'), findsOneWidget);
  });
}
