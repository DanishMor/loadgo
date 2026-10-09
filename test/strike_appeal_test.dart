import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_appeals_screen.dart';
import 'package:transport_app/core/chat/strike_appeal_screen.dart';
import 'package:transport_app/core/comm/chat_strikes.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/server_clock.dart';
import 'package:transport_app/core/services/strike_appeal_service.dart';

import 'test_utils.dart';

/// MASTER-6 Task 34: strike appeals.
void main() {
  late FakeFirebaseFirestore db;
  String? uid;
  final now = DateTime(2026, 10, 9, 12);

  setUp(() async {
    ServerClock.reset();
    db = FakeFirebaseFirestore();
    uid = 'u1';
    Backend.useFakes(db: db, uid: () => uid);
    languageNotifier.value = AppLanguage.english;
  });

  Future<void> strike(String id, DateTime at, {String kind = 'phone'}) => db.collection('violations').doc(id).set({'userId': 'u1', 'kind': kind, 'excerpt': 'call me', 'bookingId': 'b1', 'createdAt': Timestamp.fromDate(at)});

  test('granting takes one strike off; the suspension and the review go when the lower count no longer needs them', () {
    var o = AppealOutcome.grant(5);
    expect((o.strikes, o.liftBlock, o.clearReview), (4, false, true)); // 4 strikes still mean 3 days; review is for 5+
    o = AppealOutcome.grant(4);
    expect((o.strikes, o.liftBlock, o.clearReview), (3, false, true)); // 3 strikes still mean 24 h
    o = AppealOutcome.grant(3);
    expect((o.strikes, o.liftBlock), (2, true)); // 2 is only a warning
    o = AppealOutcome.grant(1);
    expect((o.strikes, o.liftBlock), (0, true));
    expect(AppealOutcome.grant(0).strikes, 0); // never negative
  });

  test('the appeal window is 14 days from the strike', () {
    expect(AppealOutcome.open(now, now.add(const Duration(days: 13, hours: 23))), isTrue);
    expect(AppealOutcome.open(now, now.add(const Duration(days: 14))), isFalse);
  });

  test('a person sees their own strikes newest first with the appeal state', () async {
    await strike('u1_1', now.subtract(const Duration(days: 30)));
    await strike('u1_2', now.subtract(const Duration(days: 2)));
    await db.collection('violations').doc('x_1').set({'userId': 'someoneElse', 'kind': 'upi', 'excerpt': 'x', 'createdAt': Timestamp.fromDate(now)});
    await db.collection('strike_appeals').doc('u1_2').set({'userId': 'u1', 'violationId': 'u1_2', 'text': 'It was my own order number', 'status': 'granted', 'note': 'Sorry about that'});
    final list = await StrikeAppealService.mine();
    expect(list.map((s) => s.id), ['u1_2', 'u1_1']);
    expect(list.first.appeal!.status, 'granted');
    expect(list.first.canAppeal(now), isFalse); // already appealed
    expect(list.last.canAppeal(now), isFalse); // too old
  });

  test('appeal: text 10 to 300 characters, once, inside the window', () async {
    await strike('u1_1', now.subtract(const Duration(days: 2)));
    await strike('u1_0', now.subtract(const Duration(days: 40)));
    final recent = (await StrikeAppealService.mine()).firstWhere((s) => s.id == 'u1_1');
    final old = (await StrikeAppealService.mine()).firstWhere((s) => s.id == 'u1_0');
    await expectLater(StrikeAppealService.appeal(recent, 'too short', now: now), throwsA(isA<AppealException>().having((e) => e.reason, 'r', 'text')));
    await expectLater(StrikeAppealService.appeal(recent, 'x' * 301, now: now), throwsA(isA<AppealException>().having((e) => e.reason, 'r', 'text')));
    await expectLater(StrikeAppealService.appeal(old, 'This was too long ago to count', now: now), throwsA(isA<AppealException>().having((e) => e.reason, 'r', 'closed')));
    await StrikeAppealService.appeal(recent, '  The number was my order id, not a phone  ', now: now);
    final d = (await db.collection('strike_appeals').doc('u1_1').get()).data()!;
    expect((d['userId'], d['status'], d['text']), ('u1', 'pending', 'The number was my order id, not a phone'));
    final again = (await StrikeAppealService.mine()).firstWhere((s) => s.id == 'u1_1');
    await expectLater(StrikeAppealService.appeal(again, 'A second try for the same strike', now: now), throwsA(isA<AppealException>().having((e) => e.reason, 'r', 'exists')));
  });

  test('admin: granting lowers the strikes and lifts the suspension, writes the note and an audit row; rejecting changes nothing about the person', () async {
    await db.collection('users').doc('u1').set({'chatStrikes': 3, 'chatBlockedUntil': Timestamp.fromDate(now.add(const Duration(hours: 5))), 'chatReview': false});
    await db.collection('strike_appeals').doc('u1_1').set({'userId': 'u1', 'violationId': 'u1_1', 'text': 'It was my order number', 'status': 'pending'});
    uid = 'admin1';
    final a = (await StrikeAppealService.watchPending().first).single;
    await StrikeAppealService.decide(a, grant: true, note: 'Checked, it was an order id');
    var user = (await db.collection('users').doc('u1').get()).data()!;
    expect(user['chatStrikes'], 2);
    expect(user.containsKey('chatBlockedUntil'), isFalse);
    final ap = (await db.collection('strike_appeals').doc('u1_1').get()).data()!;
    expect((ap['status'], ap['handledBy'], ap['note']), ('granted', 'admin1', 'Checked, it was an order id'));
    expect((await db.collection('audit_events').get()).docs.single.data()['data']['action'], 'strike_appeal_granted');
    expect(await StrikeAppealService.watchPending().first, isEmpty);

    await db.collection('strike_appeals').doc('u1_2').set({'userId': 'u1', 'violationId': 'u1_2', 'text': 'Trust me on this one', 'status': 'pending'});
    await StrikeAppealService.decide((await StrikeAppealService.watchPending().first).single, grant: false, note: 'It did contain a number');
    user = (await db.collection('users').doc('u1').get()).data()!;
    expect(user['chatStrikes'], 2); // unchanged
    expect((await db.collection('strike_appeals').doc('u1_2').get()).data()!['status'], 'rejected');
  });

  testWidgets('the person\'s screen lists strikes, appeals one, and shows the answer on another', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    MyStrike s(String id, {StrikeAppeal? appeal, int daysAgo = 2}) => MyStrike(id: id, kind: 'phone', excerpt: 'call me', at: DateTime.now().subtract(Duration(days: daysAgo)), appeal: appeal);
    MyStrike? sent;
    String? sentText;
    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(home: StrikeAppealScreen(
        load: () async => [s('u1_3'), s('u1_2', appeal: const StrikeAppeal(violationId: 'u1_2', userId: 'u1', text: 't', status: 'granted', note: 'Sorry')), s('u1_1', daysAgo: 30)],
        send: (st, t) async {
          sent = st;
          sentText = t;
        },
      )),
    ));
    await settle(tester);
    expect(find.byKey(const ValueKey('apAppeal_u1_3')), findsOneWidget);
    expect(find.byKey(const ValueKey('apAppeal_u1_2')), findsNothing);
    expect(find.byKey(const ValueKey('apAppeal_u1_1')), findsNothing);
    expect(find.text('Accepted: one strike was taken off: Sorry'), findsOneWidget);
    expect(find.text('The time to appeal this strike has passed.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('apAppeal_u1_3')));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('apText')), 'That was my order number');
    await tester.tap(find.byKey(const ValueKey('apSend')));
    await settle(tester);
    expect(sent?.id, 'u1_3');
    expect(sentText, 'That was my order number');
  });

  testWidgets('the admin screen shows the reason and decides with a note', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    StrikeAppeal? decided;
    bool? granted;
    String? note;
    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(home: AdminAppealsScreen(
        appeals: Stream.value(const [StrikeAppeal(violationId: 'u1_1', userId: 'u1', text: 'It was my order number', status: 'pending')]),
        decide: (a, g, n) async {
          decided = a;
          granted = g;
          note = n;
        },
      )),
    ));
    await settle(tester);
    expect(find.text('It was my order number'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('appealGrant_u1_1')));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('apNote')), 'Checked');
    await tester.tap(find.byKey(const ValueKey('apDecideOk')));
    await settle(tester);
    expect((decided?.violationId, granted, note), ('u1_1', true, 'Checked'));
  });
}
