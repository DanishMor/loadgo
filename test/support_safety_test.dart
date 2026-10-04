import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/support_ticket.dart';
import 'package:transport_app/core/safety/emergency_contacts_screen.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/safety_service.dart';
import 'package:transport_app/core/services/support_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/core/support/support_screens.dart';
import 'package:transport_app/core/widgets/common.dart';
import 'package:transport_app/driver/trip_safety_card.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  String? uid;

  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => uid);
    languageNotifier.value = AppLanguage.english;
  });

  Future<Booking> booking() async {
    uid = 'customer1';
    final loadId = await LoadService.post(
        pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: null,
        pickupDate: DateTime(2026, 10, 5), notes: '');
    uid = 'driver1';
    final vid = await VehicleService.add(number: 'MH12AB1234', type: '14ft', capacity: 4, rcNumber: 'RC1');
    final v = (await VehicleService.fetchMyActive()).firstWhere((x) => x.id == vid);
    final id = await BookingService.accept(loadId: loadId, vehicle: v);
    return Booking.fromDoc(await db.collection('bookings').doc(id).get());
  }

  group('tickets', () {
    test('create, reply, escalate to 3, close', () async {
      uid = 'customer1';
      final id = await SupportService.create(category: TicketCategory.payment, subject: ' Refund? ', description: 'x');
      var t = (await SupportService.watch(id).first)!;
      expect(t.subject, 'Refund?');
      expect(t.status, TicketStatus.open);
      await SupportService.reply(id, 'Hello');
      expect((await SupportService.watchReplies(id).first).single.text, 'Hello');
      for (var i = 0; i < 3; i++) {
        await SupportService.escalate((await SupportService.watch(id).first)!);
      }
      t = (await SupportService.watch(id).first)!;
      expect(t.escalationLevel, 3);
      expect(t.canEscalate, isFalse);
      expect(() => SupportService.escalate(t), throwsStateError);
      await SupportService.close(id);
      expect((await SupportService.watch(id).first)!.isOpen, isFalse);
      expect((await SupportService.watchMine().first).single.id, id);
    });

    test('disputes need a booking; safety tickets are urgent', () async {
      uid = 'customer1';
      expect(() => SupportService.create(category: TicketCategory.dispute, subject: 'Damage'), throwsArgumentError);
      final id = await SupportService.create(category: TicketCategory.safety, subject: 'Unsafe driving', priority: TicketPriority.low);
      expect((await SupportService.watch(id).first)!.priority, TicketPriority.urgent);
    });

    test('reply length is limited', () async {
      uid = 'customer1';
      final id = await SupportService.create(category: TicketCategory.other, subject: 'Hi there');
      expect(() => SupportService.reply(id, ' '), throwsArgumentError);
      expect(() => SupportService.reply(id, 'x' * 1001), throwsArgumentError);
    });
  });

  group('safety', () {
    test('SOS uses the booking location; breakdown flags booking and notifies customer', () async {
      final b = await booking();
      await db.collection('bookings').doc(b.id).update({'lastKnownLocation': const GeoPoint(26.9, 75.8)});
      final live = Booking.fromDoc(await db.collection('bookings').doc(b.id).get());
      uid = 'driver1';
      final sosId = await SafetyService.sendSos(booking: live);
      final sos = (await db.collection('sos_alerts').doc(sosId).get()).data()!;
      expect(sos['userId'], 'driver1');
      expect(sos['bookingId'], b.id);
      expect((sos['location'] as GeoPoint).latitude, 26.9);

      await SafetyService.reportBreakdown(live, note: ' tyre burst ');
      final after = Booking.fromDoc(await db.collection('bookings').doc(b.id).get());
      expect(after.breakdown!.note, 'tyre burst');
      expect(after.breakdown!.replacementRequested, isTrue);
      final notes = (await db.collection('notifications').where('userId', isEqualTo: 'customer1').get()).docs;
      expect(notes.map((n) => n['type']), contains('breakdown_reported'));
    });

    test('emergency contacts: up to three', () async {
      uid = 'u1';
      await db.collection('users').doc('u1').set({'phone': '+91'});
      await SafetyService.saveContacts(const [EmergencyContact('Maa', '+919800000001')]);
      expect(SafetyService.contactsFrom((await db.collection('users').doc('u1').get()).data()).single.name, 'Maa');
      expect(() => SafetyService.saveContacts(List.filled(4, const EmergencyContact('X', '+919800000001'))), throwsArgumentError);
    });
  });

  Widget app(Widget home) => LanguageScope(notifier: languageNotifier, child: MaterialApp(home: home));

  testWidgets('new ticket form requires a booking for disputes', (tester) async {
    uid = 'customer1';
    await tester.pumpWidget(app(const NewTicketScreen()));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('ticketCategory')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dispute').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('ticketSubject')), 'Goods damaged');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(PrimaryButton));
    await tester.tap(find.byType(PrimaryButton));
    await tester.pumpAndSettle();
    expect(find.text('Choose the booking you want to dispute'), findsOneWidget);
    expect((await tester.runAsync(() => db.collection('tickets').get()))!.docs, isEmpty);
  });

  testWidgets('emergency contacts screen adds a contact', (tester) async {
    uid = 'u1';
    await tester.runAsync(() => db.collection('users').doc('u1').set({'phone': '+91'}));
    await tester.pumpWidget(app(const EmergencyContactsScreen()));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('addContact')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('contactName')), 'Bhai');
    await tester.enterText(find.byKey(const ValueKey('contactPhone')), '9800000002');
    await tester.tap(find.byKey(const ValueKey('contactSave')));
    await settle(tester);
    expect(find.text('Bhai'), findsOneWidget);
    expect(find.text('+919800000002'), findsOneWidget);
  });

  testWidgets('driver SOS asks first, then records the alert', (tester) async {
    final b = (await tester.runAsync(booking))!;
    uid = 'driver1';
    await tester.pumpWidget(app(Scaffold(body: TripSafetyCard(booking: b))));
    await tester.tap(find.byKey(const ValueKey('sosButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sosConfirm')));
    await settle(tester);
    expect(find.textContaining('Call 112 if you are in danger'), findsOneWidget);
    expect((await tester.runAsync(() => db.collection('sos_alerts').get()))!.docs, hasLength(1));
  });
}
