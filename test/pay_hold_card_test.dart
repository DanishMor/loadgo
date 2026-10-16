import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/documents/payment_card.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';

Booking _b({Map<String, Object?> extra = const {}, String status = 'in_transit'}) => Booking.fromMap('b1', {
      'customerId': 'customer1', 'driverId': 'driver1', 'status': status, 'agreedFarePaise': 1000000, 'paymentStatus': 'pending',
      'pickup': 'Delhi', 'drop': 'Jaipur', 'loadId': 'l', 'vehicleId': 'v', 'cargoType': 'FMCG', 'weight': 2, 'vehicleType': '14ft',
      'notes': '', 'vehicleNumber': 'N', 'driverName': 'D', 'driverPhone': '1', 'timeline': <String, Object?>{}, ...extra,
    });

void main() {
  late String uid;
  setUp(() {
    uid = 'customer1';
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => uid);
    languageNotifier.value = AppLanguage.english;
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.paymentGateway: true});
  });
  tearDown(FeaturesService.reset);

  Future<void> show(WidgetTester t, Booking b) => t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PaymentCard(key: UniqueKey(), booking: b)))));

  test('the held amount is read from the booking; a booking without a hold has none', () {
    expect(_b(extra: {'paymentHold': {'orderId': 'o1', 'paise': 1000000}}).heldPaise, 1000000);
    expect(_b().heldPaise, isNull);
    expect(_b(extra: {'paymentHold': 'junk'}).heldPaise, isNull);
    expect(_b(extra: {'paymentHold': {'paise': 'x'}}).heldPaise, isNull);
  });

  testWidgets('while money is held the customer sees the line and no pay or "I have paid" button, and the driver cannot confirm by hand', (tester) async {
    final held = _b(extra: {'paymentHold': {'orderId': 'o1', 'paise': 1000000}});
    await show(tester, held);
    expect(find.byKey(const ValueKey('payHeldLine')), findsOneWidget);
    expect(find.textContaining('Held safely'), findsOneWidget);
    expect(find.byKey(const ValueKey('payOnline')), findsNothing);
    expect(find.byKey(const ValueKey('markPaid')), findsNothing);
    uid = 'driver1';
    await show(tester, held);
    expect(find.byKey(const ValueKey('confirmReceived')), findsNothing);
  });

  testWidgets('without a hold the customer still has both ways to pay', (tester) async {
    await show(tester, _b());
    expect(find.byKey(const ValueKey('payHeldLine')), findsNothing);
    expect(find.byKey(const ValueKey('payOnline')), findsOneWidget);
    expect(find.byKey(const ValueKey('markPaid')), findsOneWidget);
  });
}
