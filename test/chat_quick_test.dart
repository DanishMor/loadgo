import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/chat/chat_helpers.dart';
import 'package:transport_app/core/chat/chat_screen.dart';
import 'package:transport_app/core/comm/contact_filter.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/chat_message.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/chat_service.dart';
import 'package:transport_app/core/services/rate_limit_service.dart';

import 'test_utils.dart';

/// MASTER-6 Task 33: quick replies, read ticks, the hourly message hint.
void main() {
  late FakeFirebaseFirestore db;
  String? uid;
  late Booking booking;

  setUp(() async {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => uid);
    languageNotifier.value = AppLanguage.english;
    uid = 'customer1';
    await db.collection('bookings').doc('B1').set({
      'loadId': 'L1', 'driverId': 'driver1', 'vehicleId': 'v1', 'customerId': 'customer1', 'status': 'accepted', 'pickup': 'Delhi', 'drop': 'Jaipur', 'cargoType': 'FMCG', 'weight': 2,
      'vehicleType': '14ft', 'vehicleNumber': 'MH12AB1234', 'driverName': 'Ramesh', 'driverPhone': '', 'timeline': <String, dynamic>{}, 'createdAt': Timestamp.now(), 'updatedAt': Timestamp.now(),
    });
    booking = Booking.fromDoc(await db.collection('bookings').doc('B1').get());
  });

  test('every quick reply, in every language, is clean for the contact filter (no number, no link, no call-me)', () {
    final ids = {...ChatHelpers.driverReplies, ...ChatHelpers.customerReplies};
    for (final lang in AppLanguage.values) {
      for (final id in ids) {
        final text = T.get('qr_$id', lang);
        expect(text.isNotEmpty && text != 'qr_$id', isTrue, reason: '$lang $id');
        expect(text.length, lessThanOrEqualTo(ChatMessage.maxLength));
        expect(ContactFilter.check(text), isNull, reason: '$lang $id: $text');
      }
    }
  });

  test('driver and customer get their own lines; thanks and ok are shared', () {
    expect(ChatHelpers.repliesFor(isDriver: true), contains('onMyWay'));
    expect(ChatHelpers.repliesFor(isDriver: false), contains('goodsReady'));
    expect(ChatHelpers.repliesFor(isDriver: false), isNot(contains('onMyWay')));
    for (final r in [true, false]) {
      expect(ChatHelpers.repliesFor(isDriver: r), containsAll(['thanks', 'ok']));
    }
  });

  test('seen: only once the other person read at or after the message; no time yet means sent', () {
    final m = ChatMessage(id: 'm', senderId: 'a', text: 't', createdAt: DateTime(2026, 10, 9, 12));
    expect(ChatHelpers.isSeen(m, null), isFalse);
    expect(ChatHelpers.isSeen(m, DateTime(2026, 10, 9, 11, 59)), isFalse);
    expect(ChatHelpers.isSeen(m, DateTime(2026, 10, 9, 12)), isTrue);
    expect(ChatHelpers.isSeen(m, DateTime(2026, 10, 9, 13)), isTrue);
    expect(ChatHelpers.isSeen(const ChatMessage(id: 'n', senderId: 'a', text: 't'), DateTime(2030)), isFalse);
  });

  test('remaining messages: from the counter, the full limit in a fresh hour or without a counter', () async {
    final limit = RateLimit.limits[RateLimit.messageKind]!;
    expect(ChatHelpers.remaining(limit: 120, used: 100), 20);
    expect(ChatHelpers.remaining(limit: 120, used: 500), 0);
    expect(await RateLimit.remaining(RateLimit.messageKind), limit);
    final now = DateTime(2026, 10, 9, 12);
    await db.collection('rate_limits').doc('customer1_message').set({'count': 117, 'windowStart': Timestamp.fromDate(now.subtract(const Duration(minutes: 10)))});
    expect(await RateLimit.remaining(RateLimit.messageKind, now: now), limit - 117);
    expect(await RateLimit.remaining(RateLimit.messageKind, now: now.add(const Duration(hours: 1))), limit); // a new hour
  });

  test('the other person\'s read time is readable and follows their mark', () async {
    expect(await ChatService.watchOtherRead(booking).first, isNull);
    uid = 'driver1';
    await ChatService.markRead('B1');
    uid = 'customer1';
    expect(await ChatService.watchOtherRead(booking).first, isNotNull);
  });

  testWidgets('a quick reply sends at once; my message shows one tick, and two when the other person has read it', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    uid = 'customer1';
    await db.collection('users').doc('customer1').set({'name': 'Anil'});
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: ChatScreen(booking: booking))));
    await settle(tester);
    expect(find.byKey(const ValueKey('qr_goodsReady')), findsOneWidget);
    expect(find.byKey(const ValueKey('qr_onMyWay')), findsNothing); // a customer does not get the driver's lines
    await tester.tap(find.byKey(const ValueKey('qr_goodsReady')));
    await settle(tester);
    final sent = (await db.collection('bookings').doc('B1').collection('messages').get()).docs;
    expect(sent.single.data()['text'], 'The goods are ready for loading');
    expect(find.text('The goods are ready for loading'), findsWidgets);
    final id = sent.single.id;
    expect(find.byKey(ValueKey('sent_$id')), findsOneWidget);
    // the driver opens the chat
    await db.collection('bookings').doc('B1').collection('chat_reads').doc('driver1').set({'lastReadAt': Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 1)))});
    await settle(tester);
    expect(find.byKey(ValueKey('seen_$id')), findsOneWidget);
  });

  testWidgets('the driver gets his own lines; a Hindi screen shows them in Hindi', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    uid = 'driver1';
    languageNotifier.value = AppLanguage.hindi;
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: ChatScreen(booking: booking))));
    await settle(tester);
    expect(find.byKey(const ValueKey('qr_onMyWay')), findsOneWidget);
    expect(find.text('मैं रास्ते में हूँ'), findsOneWidget);
    languageNotifier.value = AppLanguage.english;
  });

  testWidgets('the hint shows how many messages are left only when few remain', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    uid = 'customer1';
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: ChatScreen(booking: booking))));
    await settle(tester);
    expect(find.byKey(const ValueKey('chatLeft')), findsNothing);
    await db.collection('rate_limits').doc('customer1_message').set({'count': 112, 'windowStart': Timestamp.now()});
    await settle(tester);
    expect(find.text('8 messages left this hour'), findsOneWidget);
  });
}
