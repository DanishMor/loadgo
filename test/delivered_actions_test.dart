import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/customer/delivered_actions.dart';
import 'package:transport_app/customer/post_load_screen.dart';


/// MASTER-6 Task 20: after delivery, rate / report / book again.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'c1');
  });

  Booking trip(String status) => Booking(
        id: 'b1', loadId: 'l1', driverId: 'd', vehicleId: 'v', customerId: 'c1', status: status, pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 3,
        vehicleType: 'Mini', budget: 9000, pickupDate: DateTime(2026, 10, 1), notes: 'Call first', vehicleNumber: 'MH12AB1', driverName: 'D', driverPhone: '1',
        timeline: const {}, extraDrops: const ['Ajmer'],
      );

  test('the draft keeps places, goods, vehicle, notes and stops, and drops the date', () {
    final l = loadDraftFromBooking(trip('delivered'));
    expect((l.pickup, l.drop, l.cargoType, l.weight, l.vehicleType, l.budget, l.notes), ('Delhi', 'Jaipur', 'FMCG', 3, 'Mini', 9000, 'Call first'));
    expect(l.extraDrops, ['Ajmer']);
    expect(l.pickupDate, isNull);
    expect(l.id, '');
  });

  test('only a change into delivered counts as a fresh delivery', () {
    expect(DeliveredWatcher.justDelivered('in_transit', 'delivered'), isTrue);
    expect(DeliveredWatcher.justDelivered('unloading', 'delivered'), isTrue);
    expect(DeliveredWatcher.justDelivered('delivered', 'delivered'), isFalse);
    expect(DeliveredWatcher.justDelivered(null, 'delivered'), isFalse); // opened already delivered
    expect(DeliveredWatcher.justDelivered('in_transit', 'in_transit'), isFalse);
    expect(DeliveredWatcher.justDelivered('in_transit', 'cancelled'), isFalse);
  });

  testWidgets('Book again opens Post Load filled from the trip', (tester) async {
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: DeliveredActionsCard(booking: trip('delivered')))))));
    await tester.tap(find.byKey(const ValueKey('bookAgain')));
    await tester.pumpAndSettle();
    expect(find.byType(PostLoadScreen), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Delhi'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Jaipur'), findsOneWidget);
  });

  testWidgets('the sheet appears once when the trip becomes delivered while open, and not for an already delivered trip', (tester) async {
    Widget app(Booking b) => LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: ListView(children: [DeliveredWatcher(booking: b, child: const SizedBox.shrink()), const SizedBox(height: 600)]))));
    await tester.pumpWidget(app(trip('delivered')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('deliveredSheet')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(trip('in_transit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('deliveredSheet')), findsNothing);
    await tester.pumpWidget(app(trip('delivered')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('deliveredSheet')), findsOneWidget);
    expect(find.text('Delivered!'), findsOneWidget);
    // Report a problem opens the new-ticket form for this booking
    await tester.tap(find.byKey(const ValueKey('deliveredIssue')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('deliveredSheet')), findsNothing);
    expect(find.byType(PostLoadScreen), findsNothing);
  });
}
