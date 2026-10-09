import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/safety/trip_safety_checks.dart';
import 'package:transport_app/core/safety/trip_safety_checks_card.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/safety_service.dart';


/// MASTER-6 Task 26: night prompt, rest reminder, emergency contact check.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'd1');
  });

  final start = DateTime(2026, 10, 9, 8);

  Booking trip({String status = 'in_transit', DateTime? inTransit}) => Booking(
        id: 'b1', loadId: 'b1', driverId: 'd1', vehicleId: 'v', customerId: 'c', status: status, pickup: 'Delhi', drop: 'Jaipur', cargoType: 'x', weight: 1,
        vehicleType: '20ft', budget: null, pickupDate: null, notes: '', vehicleNumber: 'MH12AB1', driverName: 'D', driverPhone: '1',
        timeline: {'picked_up': start, 'in_transit': ?inTransit},
      );

  test('night is 22:00 to 04:59 local time, and only while driving', () {
    expect([for (final h in [21, 22, 23, 0, 4, 5]) TripSafetyChecks.isNight(DateTime(2026, 10, 9, h, 59))], [false, true, true, true, true, false]);
    expect(TripSafetyChecks.nightPrompt('in_transit', DateTime(2026, 10, 9, 23)), isTrue);
    expect(TripSafetyChecks.nightPrompt('picked_up', DateTime(2026, 10, 9, 2)), isTrue);
    expect(TripSafetyChecks.nightPrompt('loading', DateTime(2026, 10, 9, 23)), isFalse);
    expect(TripSafetyChecks.nightPrompt('delivered', DateTime(2026, 10, 9, 23)), isFalse);
    expect(TripSafetyChecks.nightPrompt('in_transit', DateTime(2026, 10, 9, 12)), isFalse);
  });

  test('rest: due after 4 hours of driving, restarts from the last break, never before driving', () {
    final b = trip(inTransit: start);
    expect(TripSafetyChecks.restDue(b, start.add(const Duration(hours: 3, minutes: 59)), null), isFalse);
    expect(TripSafetyChecks.restDue(b, start.add(const Duration(hours: 4)), null), isTrue);
    expect(TripSafetyChecks.hoursDriving(b, start.add(const Duration(hours: 5, minutes: 30)), null), 5);
    final breakAt = start.add(const Duration(hours: 4));
    expect(TripSafetyChecks.restDue(b, start.add(const Duration(hours: 6)), breakAt), isFalse); // 2 h since the break
    expect(TripSafetyChecks.restDue(b, start.add(const Duration(hours: 8)), breakAt), isTrue);
    expect(TripSafetyChecks.restDue(b, start.add(const Duration(hours: 9)), start.subtract(const Duration(hours: 5))), isTrue); // an old break from before the trip does not count
    expect(TripSafetyChecks.restDue(trip(status: 'loading'), start.add(const Duration(hours: 9)), null), isFalse);
    expect(TripSafetyChecks.restDue(trip(status: 'delivered'), start.add(const Duration(hours: 9)), null), isFalse);
  });

  test('contacts: none, valid, or some invalid', () {
    expect(TripSafetyChecks.contacts(const []).none, isTrue);
    final ok = TripSafetyChecks.contacts(const [EmergencyContact('Mum', '98765 43210'), EmergencyContact('Bro', '+91 9123456780')]);
    expect((ok.ok, ok.valid), (true, 2));
    final bad = TripSafetyChecks.contacts(const [EmergencyContact('Mum', '98765 43210'), EmergencyContact('Bad', '12345')]);
    expect((bad.ok, bad.invalid, bad.valid), (false, 1, 1));
  });

  testWidgets('the card shows the contacts warning, the night prompt and the rest reminder; "I took a break" clears the reminder', (tester) async {
    var now = DateTime(2026, 10, 9, 23, 30);
    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: TripSafetyChecksCard(booking: trip(inTransit: start), now: () => now, loadContacts: () async => const [EmergencyContact('Bad', '123')])))),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('safetyContacts')), findsOneWidget);
    expect(find.textContaining('1 emergency contact number(s) are not valid'), findsOneWidget);
    expect(find.byKey(const ValueKey('safetyNight')), findsOneWidget);
    expect(find.byKey(const ValueKey('safetyRest')), findsOneWidget);
    expect(find.textContaining('about 15 hours'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tscTookBreak')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('safetyRest')), findsNothing);
    // a rebuilt card remembers the break
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: TripSafetyChecksCard(booking: trip(inTransit: start), now: () => now, loadContacts: () async => const [EmergencyContact('Mum', '9876543210')])))),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('safetyRest')), findsNothing);
    expect(find.byKey(const ValueKey('safetyContacts')), findsNothing);
    now = now.add(const Duration(hours: 4));
  });

  testWidgets('nothing to say shows nothing', (tester) async {
    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(home: Scaffold(body: TripSafetyChecksCard(booking: trip(inTransit: start), now: () => start.add(const Duration(hours: 1)), loadContacts: () async => const [EmergencyContact('Mum', '9876543210')]))),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tripSafetyChecks')), findsNothing);
  });
}
