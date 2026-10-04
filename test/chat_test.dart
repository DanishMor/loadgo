import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/chat/chat_screen.dart';
import 'package:transport_app/core/chat/off_platform.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/chat_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';

import 'test_utils.dart';

void main() {
  group('off-platform detector', () {
    test('phone numbers', () {
      expect(offPlatformReason('call 9876543210'), OffPlatformReason.phone);
      expect(offPlatformReason('+91 98765 43210 pe call karo'), OffPlatformReason.phone);
      expect(offPlatformReason('98765-43210'), OffPlatformReason.phone);
      expect(offPlatformReason('Load is 12000 kg'), isNull);
      expect(offPlatformReason('Invoice 1234567890123'), isNull, reason: 'longer digit runs are not phones');
    });

    test('UPI ids and phrases', () {
      expect(offPlatformReason('send to ramesh.k@okaxis'), OffPlatformReason.upi);
      expect(offPlatformReason('9876543210@ybl'), OffPlatformReason.upi);
      expect(offPlatformReason('mail me at a@gmail.com'), isNull);
      expect(offPlatformReason('Pay outside the app, cheaper'), OffPlatformReason.phrase);
      expect(offPlatformReason('app ke bahar payment karo'), OffPlatformReason.phrase);
      expect(offPlatformReason('Reached the gate, loading now'), isNull);
    });
  });

  late FakeFirebaseFirestore db;
  String? uid;
  late Booking booking;

  setUp(() async {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => uid);
    languageNotifier.value = AppLanguage.english;
    uid = 'customer1';
    final loadId = await LoadService.post(
        pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: null,
        pickupDate: DateTime(2026, 10, 5), notes: '');
    uid = 'driver1';
    final vid = await VehicleService.add(number: 'MH12AB1234', type: '14ft', capacity: 4, rcNumber: 'RC1');
    final v = (await VehicleService.fetchMyActive()).firstWhere((x) => x.id == vid);
    final id = await BookingService.accept(loadId: loadId, vehicle: v);
    booking = Booking.fromDoc(await db.collection('bookings').doc(id).get());
  });

  test('send, flag, unread count and read marks', () async {
    uid = 'driver1';
    expect(ChatService.otherParty(booking), 'customer1');
    await ChatService.send(booking, '  Reaching in 20 min ');
    await ChatService.send(booking, 'my upi is ramesh@ybl');
    final msgs = await ChatService.watch(booking.id).first;
    expect(msgs.map((m) => m.text), ['Reaching in 20 min', 'my upi is ramesh@ybl']);
    expect(msgs.map((m) => m.flagged), [false, true]);
    expect(await ChatService.watchUnread(booking.id).first, 0, reason: 'own messages are never unread');

    uid = 'customer1';
    expect(ChatService.otherParty(booking), 'driver1');
    expect(await ChatService.watchUnread(booking.id).first, 2);
    await ChatService.markRead(booking.id);
    expect(await ChatService.watchUnread(booking.id).first, 0);
  });

  test('empty and too-long messages are refused', () async {
    uid = 'driver1';
    await expectLater(ChatService.send(booking, '   '), throwsA(isA<ChatSendException>()));
    await expectLater(ChatService.send(booking, 'x' * 501), throwsA(isA<ChatSendException>()));
    expect((await db.collection('bookings').doc(booking.id).collection('messages').get()).docs, isEmpty);
  });

  test('block / unblock and reports', () async {
    uid = 'customer1';
    await ChatService.block('driver1');
    expect(await ChatService.watchBlocked('driver1').first, isTrue);
    await ChatService.unblock('driver1');
    expect(await ChatService.watchBlocked('driver1').first, isFalse);

    await ChatService.report(booking, reason: ReportReason.offPlatform, details: ' asked for cash ');
    final r = (await db.collection('reports').get()).docs.single.data();
    expect(r['reporterId'], 'customer1');
    expect(r['reportedId'], 'driver1');
    expect(r['details'], 'asked for cash');
    expect(r['status'], 'open');
  });

  testWidgets('chat screen warns before sending contact details and shows the flag', (tester) async {
    uid = 'customer1';
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: ChatScreen(booking: booking))));
    await settle(tester);
    expect(find.text('No messages yet. Say hello!'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('chatInput')), 'call me on 9876543210');
    await tester.tap(find.byKey(const ValueKey('chatSend')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Send anyway?'), findsOneWidget);
    await tester.tap(find.text('Send anyway'));
    await settle(tester);
    expect(find.text('call me on 9876543210'), findsOneWidget);
    expect(find.text('May share contact or payment details'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('chatInput')), 'Thanks');
    await tester.tap(find.byKey(const ValueKey('chatSend')));
    await settle(tester);
    expect(find.text('Thanks'), findsOneWidget);
  });

  testWidgets('chat button shows the unread badge', (tester) async {
    uid = 'driver1';
    await tester.runAsync(() => ChatService.send(booking, 'Hello'));
    uid = 'customer1';
    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(home: Scaffold(body: BookingChatButton(booking: booking))),
    ));
    await settle(tester);
    expect(find.text('1'), findsOneWidget);
  });
}
