import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/admin/admin_violations_screen.dart';
import 'package:transport_app/core/call/call_controller.dart';
import 'package:transport_app/core/call/call_models.dart';
import 'package:transport_app/core/call/call_provider.dart';
import 'package:transport_app/core/call/call_screens.dart';
import 'package:transport_app/core/call/call_signaling.dart';
import 'package:transport_app/core/comm/chat_strikes.dart';
import 'package:transport_app/core/comm/contact_filter.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/services/audit_service.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/chat_service.dart';
import 'package:transport_app/core/services/comm_admin_service.dart';
import 'package:transport_app/core/services/comm_guard.dart';
import 'package:transport_app/core/widgets/admin_phone.dart';
import 'package:transport_app/core/widgets/booking_widgets.dart';

import 'test_utils.dart';

/// A call provider that never touches the network: it records what the
/// controller asked for and reports "connected" once both sides are set.
class FakeCallProvider implements CallProvider {
  FakeCallProvider({this.micDenied = false, this.isSupported = true});

  final bool micDenied;
  final bool isSupported;
  final log = <String>[];
  final _cand = StreamController<CallCandidate>();
  final _conn = StreamController<bool>();
  bool closed = false;

  @override
  bool get supported => isSupported;

  @override
  Future<void> init() async {
    log.add('init');
    if (micDenied) throw MicDeniedException();
  }

  @override
  Future<String> createOffer() async {
    log.add('createOffer');
    Future<void>.delayed(const Duration(milliseconds: 5), () => _cand.isClosed ? null : _cand.add(const CallCandidate(from: '', candidate: 'candidate:caller', sdpMid: '0', sdpMLineIndex: 0)));
    return 'v=0 fake offer sdp for the caller side';
  }

  @override
  Future<String> acceptOffer(String offerSdp) async {
    log.add('acceptOffer');
    Future<void>.delayed(const Duration(milliseconds: 5), () {
      if (_cand.isClosed) return;
      _cand.add(const CallCandidate(from: '', candidate: 'candidate:callee', sdpMid: '0', sdpMLineIndex: 0));
      _conn.add(true);
    });
    return 'v=0 fake answer sdp for the callee side';
  }

  @override
  Future<void> setAnswer(String answerSdp) async {
    log.add('setAnswer');
    Future<void>.delayed(const Duration(milliseconds: 5), () => _conn.isClosed ? null : _conn.add(true));
  }

  @override
  Future<void> addRemoteCandidate(CallCandidate c) async => log.add('remote:${c.candidate}');

  @override
  Stream<CallCandidate> get localCandidates => _cand.stream;

  @override
  Stream<bool> get connected => _conn.stream;

  @override
  Future<void> setMuted(bool muted) async => log.add('mute:$muted');

  @override
  Future<void> setSpeaker(bool on) async => log.add('speaker:$on');

  @override
  Future<void> close() async {
    closed = true;
    log.add('close');
  }
}

Booking bk(String status, {String? assigned, String driver = 'driver1'}) => Booking(
      id: 'B1', loadId: 'L1', driverId: driver, vehicleId: 'v1', customerId: 'customer1', status: status, pickup: 'Delhi', drop: 'Jaipur', cargoType: 'x', weight: 1,
      vehicleType: '20ft', budget: null, pickupDate: null, notes: '', vehicleNumber: 'MH12AB1234', driverName: 'Ramesh', driverPhone: '', timeline: const {},
      assignedDriverId: assigned,
    );

void main() {
  late FakeFirebaseFirestore db;
  String? uid;
  final t0 = DateTime(2026, 10, 8, 10);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => uid);
    languageNotifier.value = AppLanguage.english;
    callProviderFactory = FakeCallProvider.new;
    uid = 'customer1';
    await db.collection('users').doc('customer1').set({'name': 'Anil', 'phone': '+919800000001'});
    await db.collection('users').doc('driver1').set({'driverName': 'Ramesh', 'phone': '+919800000002'});
    await db.collection('bookings').doc('B1').set({
      'loadId': 'L1', 'driverId': 'driver1', 'customerId': 'customer1', 'status': 'in_transit', 'pickup': 'Delhi', 'drop': 'Jaipur', 'vehicleNumber': 'MH12AB1234', 'driverName': 'Ramesh',
    });
  });

  group('strike ladder (pure)', () {
    test('warnings, then 24 hours, 3 days, 7 days with review', () {
      expect([for (var s = 0; s <= 6; s++) ChatLadder.blockFor(s)], [null, null, null, const Duration(hours: 24), const Duration(days: 3), const Duration(days: 7), const Duration(days: 7)]);
      expect([for (var s = 0; s <= 6; s++) ChatLadder.needsReview(s)], [false, false, false, false, false, true, true]);
    });

    test('one strike comes off after 30 clean days, never with none or too early', () {
      final last = DateTime(2026, 9, 1);
      expect(ChatLadder.canDecay(strikes: 2, lastChange: last, now: DateTime(2026, 9, 30)), isFalse);
      expect(ChatLadder.canDecay(strikes: 2, lastChange: last, now: DateTime(2026, 10, 1)), isTrue);
      expect(ChatLadder.canDecay(strikes: 0, lastChange: last, now: DateTime(2027)), isFalse);
      expect(ChatLadder.canDecay(strikes: 1, lastChange: null, now: DateTime(2027)), isFalse);
    });
  });

  group('strikes and suspension (CommGuard)', () {
    Future<ViolationOutcome> strike([ContactKind k = ContactKind.phone]) => CommGuard.recordViolation(bookingId: 'B1', kind: k, text: 'call 9876543210', now: t0);

    test('1 and 2 warn; 3, 4 and 5 suspend for 24 hours, 3 days and 7 days; 5 asks for review', () async {
      uid = 'customer1';
      var o = await strike();
      expect((o.strikes, o.warningOnly, o.recorded), (1, true, true));
      o = await strike(ContactKind.upi);
      expect((o.strikes, o.warningOnly), (2, true));
      o = await strike();
      expect(o.strikes, 3);
      expect(o.blockedUntil, t0.add(const Duration(hours: 24)));
      expect(o.review, isFalse);
      o = await strike();
      expect(o.blockedUntil, t0.add(const Duration(days: 3)));
      o = await strike();
      expect(o.blockedUntil, t0.add(const Duration(days: 7)));
      expect(o.review, isTrue);
      final u = (await db.collection('users').doc('customer1').get()).data()!;
      expect((u['chatStrikes'], u['chatSeq'], u['chatReview']), (5, 5, true));
      final ids = (await db.collection('violations').get()).docs.map((d) => d.id).toList()..sort();
      expect(ids, ['customer1_1', 'customer1_2', 'customer1_3', 'customer1_4', 'customer1_5']);
      expect((await db.collection('violations').doc('customer1_2').get()).data()!['kind'], 'upi');
    });

    test('while suspended chat and calls refuse; after the time they work again', () async {
      uid = 'customer1';
      for (var i = 0; i < 3; i++) {
        await strike();
      }
      await expectLater(CommGuard.ensureAllowed(now: t0.add(const Duration(hours: 5))), throwsA(isA<ChatBlockedException>()));
      expect((await CommGuard.ensureAllowed(now: t0.add(const Duration(hours: 25)))).strikes, 3);
    });

    test('a suspended person cannot send a message, and nothing is stored', () async {
      uid = 'customer1';
      await db.collection('users').doc('customer1').update({'chatBlockedUntil': Timestamp.fromDate(DateTime.now().add(const Duration(hours: 5)))});
      final b = Booking.fromDoc(await db.collection('bookings').doc('B1').get());
      await expectLater(ChatService.send(b, 'Hello'), throwsA(isA<ChatBlockedException>()));
      expect((await db.collection('bookings').doc('B1').collection('messages').get()).docs, isEmpty);
    });

    test('thirty clean days take one strike off, once', () async {
      uid = 'customer1';
      await strike();
      await strike();
      expect(await CommGuard.decayIfDue(now: t0.add(const Duration(days: 5))), isFalse);
      // The fake stamps strikeAt with "now"; move it back to test the 30 days.
      await db.collection('users').doc('customer1').update({'chatStrikeAt': Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 31)))});
      expect(await CommGuard.decayIfDue(), isTrue);
      expect((await CommGuard.status()).strikes, 1);
      expect(await CommGuard.decayIfDue(), isFalse, reason: 'the clock restarted');
    });

    test('the violation keeps what was typed (for admins), cut to 120 characters', () async {
      uid = 'customer1';
      await CommGuard.recordViolation(bookingId: 'B1', kind: ContactKind.phone, text: '${'x' * 200} 9876543210', now: t0);
      expect(((await db.collection('violations').doc('customer1_1').get()).data()!['excerpt'] as String).length, 120);
    });
  });

  group('who rings whom', () {
    test('the customer rings the running driver; the driver and the assigned driver ring the customer', () {
      final plain = bk('in_transit');
      expect(callTarget(plain, 'customer1'), 'driver1');
      expect(callTarget(plain, 'driver1'), 'customer1');
      expect(callTarget(plain, 'stranger'), isNull);
      final company = bk('in_transit', driver: 'tr1', assigned: 'driver9');
      expect(callTarget(company, 'customer1'), 'driver9', reason: 'the assigned driver runs the trip');
      expect(callTarget(company, 'driver9'), 'customer1');
      expect(callTarget(company, 'tr1'), 'customer1');
      expect(callTarget(company, 'tr1', preferDriver: true), 'driver9');
    });

    test('calls need a confirmed, unfinished booking', () {
      for (final s in ['accepted', 'driver_arriving', 'loading', 'picked_up', 'in_transit', 'unloading']) {
        expect(bookingAllowsCall(bk(s)), isTrue, reason: s);
      }
      for (final s in ['delivered', 'cancelled', 'open', 'awaiting_approval']) {
        expect(bookingAllowsCall(bk(s)), isFalse, reason: s);
      }
    });
  });

  group('call flow (CallController with a fake provider)', () {
    CallController make({FakeCallProvider? p, Duration ring = callRingTimeout}) => CallController(p ?? FakeCallProvider(), ringTimeout: ring);

    Future<void> settleAsync() async {
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    test('ring, answer, connect, hang up: both sides end up ended; no phone number anywhere', () async {
      uid = 'customer1';
      final caller = make();
      await caller.start(booking: bk('in_transit'), calleeId: 'driver1', callerName: 'Anil');
      expect(caller.phase, CallPhase.ringing);
      await settleAsync(); // the caller's first network candidates go out as customer1
      final doc = (await db.collection('calls').get()).docs.single;
      expect(doc.data()['status'], 'ringing');
      expect(doc.data()['callerId'], 'customer1');
      expect(doc.data()['calleeId'], 'driver1');
      expect(doc.data().toString(), isNot(contains('+91')));

      uid = 'driver1';
      final ringing = await CallSignaling.watchIncoming().first;
      expect(ringing.single.callerName, 'Anil');
      final callee = make();
      await callee.answer(ringing.single);
      await settleAsync();
      expect(callee.phase, CallPhase.connected);
      expect(caller.phase, CallPhase.connected);
      expect((await db.collection('calls').doc(doc.id).get()).data()!['status'], 'accepted');

      await callee.toggleMute();
      expect(callee.muted, isTrue);
      uid = 'customer1';
      await caller.hangUp();
      await settleAsync();
      expect(caller.phase, CallPhase.ended);
      expect(callee.phase, CallPhase.ended);
      expect(callee.endReason, CallEnd.remoteEnded);
      expect((await db.collection('calls').doc(doc.id).get()).data()!['status'], 'ended');
      // Candidates were swapped both ways.
      final cands = (await db.collection('calls').doc(doc.id).collection('candidates').get()).docs.map((d) => d.data()['from']).toSet();
      expect(cands, {'customer1', 'driver1'});
    });

    test('declined, cancelled and unanswered calls', () async {
      uid = 'customer1';
      final a = make();
      await a.start(booking: bk('in_transit'), calleeId: 'driver1', callerName: 'Anil');
      uid = 'driver1';
      final incoming = (await CallSignaling.watchIncoming().first).single;
      final b = make();
      await b.decline(incoming);
      await settleAsync();
      expect(a.phase, CallPhase.ended);
      expect(a.endReason, CallEnd.declined);

      uid = 'customer1';
      final c = make();
      await c.start(booking: bk('in_transit'), calleeId: 'driver1', callerName: 'Anil');
      await c.hangUp();
      expect(c.endReason, CallEnd.cancelled);
      expect((await db.collection('calls').get()).docs.map((d) => d.data()['status']).toSet(), {'declined', 'cancelled'});

      final d = make(ring: const Duration(milliseconds: 60));
      await d.start(booking: bk('in_transit'), calleeId: 'driver1', callerName: 'Anil');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(d.endReason, CallEnd.noAnswer);
      expect((await db.collection('calls').get()).docs.map((e) => e.data()['status']).where((s) => s == 'cancelled').length, 2);
    });

    test('microphone refused, unsupported device and a suspended caller all end the call safely', () async {
      uid = 'customer1';
      final mic = make(p: FakeCallProvider(micDenied: true));
      await mic.start(booking: bk('in_transit'), calleeId: 'driver1', callerName: 'Anil');
      expect((mic.phase, mic.endReason), (CallPhase.failed, CallEnd.micDenied));

      final un = make(p: FakeCallProvider(isSupported: false));
      await un.start(booking: bk('in_transit'), calleeId: 'driver1', callerName: 'Anil');
      expect(un.endReason, CallEnd.unsupported);

      await db.collection('users').doc('customer1').update({'chatBlockedUntil': Timestamp.fromDate(DateTime.now().add(const Duration(hours: 3)))});
      final blocked = make();
      await blocked.start(booking: bk('in_transit'), calleeId: 'driver1', callerName: 'Anil');
      expect(blocked.endReason, CallEnd.blocked);
      expect((await db.collection('calls').get()).docs, isEmpty, reason: 'none of these rang anyone');
    });

    test('the callee\'s microphone refusal declines the call for the caller', () async {
      uid = 'customer1';
      final a = make();
      await a.start(booking: bk('in_transit'), calleeId: 'driver1', callerName: 'Anil');
      uid = 'driver1';
      final b = make(p: FakeCallProvider(micDenied: true));
      await b.answer((await CallSignaling.watchIncoming().first).single);
      await settleAsync();
      expect(b.endReason, CallEnd.micDenied);
      expect(a.endReason, CallEnd.declined);
    });
  });

  group('call screens', () {
    Widget host(Widget child) => LanguageScope(notifier: languageNotifier, child: MaterialApp(home: child));

    testWidgets('call button: shown while the trip is on, hidden when finished, no phone number in sight', (tester) async {
      uid = 'customer1';
      await tester.pumpWidget(host(Scaffold(body: BookingCallButton(booking: bk('in_transit')))));
      expect(find.byKey(const ValueKey('callButton')), findsOneWidget);
      expect(find.textContaining('+91'), findsNothing);
      await tester.pumpWidget(host(Scaffold(body: BookingCallButton(booking: bk('delivered')))));
      expect(find.byKey(const ValueKey('callButton')), findsNothing);
      await tester.pumpWidget(host(Scaffold(body: BookingCallButton(booking: bk('cancelled')))));
      expect(find.byKey(const ValueKey('callButton')), findsNothing);
    });

    testWidgets('an incoming call opens the answer screen once; a stale one does not ring', (tester) async {
      uid = 'driver1';
      final fresh = CallDoc(id: 'c1', bookingId: 'B1', callerId: 'customer1', calleeId: 'driver1', callerName: 'Anil', vehicleNumber: 'MH12AB1234', status: 'ringing', offerSdp: 'sdp', createdAt: DateTime.now());
      final stale = CallDoc(id: 'c0', bookingId: 'B1', callerId: 'customer1', calleeId: 'driver1', callerName: 'Old', status: 'ringing', offerSdp: 'sdp', createdAt: DateTime.now().subtract(const Duration(minutes: 5)));
      final ctrl = StreamController<List<CallDoc>>();
      await tester.pumpWidget(host(IncomingCallHost(calls: ctrl.stream, child: const Scaffold(body: Text('home')))));
      ctrl.add([stale]);
      await settle(tester);
      expect(find.byKey(const ValueKey('callAnswer')), findsNothing);
      ctrl.add([stale, fresh]);
      await settle(tester);
      expect(find.byKey(const ValueKey('callAnswer')), findsOneWidget);
      expect(find.byKey(const ValueKey('callDecline')), findsOneWidget);
      expect(find.text('Anil'), findsOneWidget);
      expect(find.text('Anil is calling you'), findsOneWidget);
      await ctrl.close();
    });

    testWidgets('the call screen shows the state and the three buttons while a call is live', (tester) async {
      uid = 'customer1';
      final c = CallController(FakeCallProvider());
      await tester.runAsync(() => c.start(booking: bk('in_transit'), calleeId: 'driver1', callerName: 'Anil', peer: 'Ramesh'));
      await tester.pumpWidget(host(CallScreen(controller: c, peer: 'Ramesh')));
      await tester.pump();
      expect(find.text('Ramesh'), findsOneWidget);
      expect(find.text('Calling Ramesh…'), findsOneWidget);
      expect(find.byKey(const ValueKey('callMute')), findsOneWidget);
      expect(find.byKey(const ValueKey('callEnd')), findsOneWidget);
      expect(find.byKey(const ValueKey('callSpeaker')), findsOneWidget);
      await tester.runAsync(c.hangUp);
      await tester.pump();
      expect(find.text('Call ended'), findsOneWidget);
      c.dispose();
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('admin: violations, suspensions, numbers, chat review', () {
    test('extend adds 7 days from now or from the end of a running suspension; lift and reset clear it; all audited', () async {
      uid = 'admin1';
      await CommAdminService.extendSuspension('customer1', now: t0);
      var u = (await db.collection('users').doc('customer1').get()).data()!;
      expect((u['chatBlockedUntil'] as Timestamp).toDate(), t0.add(const Duration(days: 7)));
      await CommAdminService.extendSuspension('customer1', now: t0.add(const Duration(days: 1)));
      u = (await db.collection('users').doc('customer1').get()).data()!;
      expect((u['chatBlockedUntil'] as Timestamp).toDate(), t0.add(const Duration(days: 14)));
      await CommAdminService.liftSuspension('customer1');
      u = (await db.collection('users').doc('customer1').get()).data()!;
      expect(u.containsKey('chatBlockedUntil'), isFalse);
      await db.collection('users').doc('customer1').update({'chatStrikes': 4});
      await CommAdminService.resetStrikes('customer1');
      expect((await db.collection('users').doc('customer1').get()).data()!['chatStrikes'], 0);
      final actions = (await db.collection('audit_events').where('type', isEqualTo: 'user_action').get()).docs.map((d) => d.data()['data']['action']).toList();
      expect(actions, containsAll(['chat_suspend_extend', 'chat_suspend_lift', 'chat_strikes_reset']));
    });

    test('showing phone numbers writes one audit line per person before it returns them', () async {
      uid = 'admin1';
      final phones = await CommAdminService.revealPhones(['customer1', 'driver1'], bookingId: 'B1');
      expect(phones, {'customer1': '+919800000001', 'driver1': '+919800000002'});
      final lines = (await db.collection('audit_events').where('type', isEqualTo: AuditType.contactView).get()).docs.map((d) => d.data()).toList();
      expect(lines.length, 2);
      expect(lines.map((l) => l['targetId']).toSet(), {'customer1', 'driver1'});
      expect(lines.every((l) => l['actorId'] == 'admin1' && l['bookingId'] == 'B1'), isTrue);
    });

    test('a chat opens for review only with a report or a dispute', () async {
      uid = 'admin1';
      await expectLater(CommAdminService.openChatForReview('B1'), throwsA(isA<NoCaseForChatException>()));
      await CommAdminService.openChatForReview('B1', reportId: 'r1');
      expect((await db.collection('chat_reviews').doc('B1').get()).data()!['reportId'], 'r1');
      expect((await db.collection('audit_events').where('type', isEqualTo: AuditType.chatView).get()).docs.length, 1);
    });

    testWidgets('an admin phone is masked until tapped, and the tap is logged first', (tester) async {
      uid = 'admin1';
      await tester.pumpWidget(LanguageScope(
        notifier: languageNotifier,
        child: const MaterialApp(home: Scaffold(body: AdminPhoneText(uid: 'driver1', phone: '+919800000002', bookingId: 'B1'))),
      ));
      expect(find.text('+919800000002'), findsNothing);
      expect(find.textContaining('•••'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('adminPhone_driver1')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(find.text('+919800000002'), findsOneWidget);
      expect((await db.collection('audit_events').where('type', isEqualTo: 'contact_view').get()).docs.length, 1);
    });

    testWidgets('violations screen: per person strikes, suspension and the actions', (tester) async {
      uid = 'admin1';
      await db.collection('users').doc('customer1').update({'chatStrikes': 3, 'chatBlockedUntil': Timestamp.fromDate(DateTime.now().add(const Duration(hours: 10)))});
      await db.collection('violations').doc('customer1_1').set({'userId': 'customer1', 'bookingId': 'B1', 'kind': 'phone', 'excerpt': 'call 98765', 'createdAt': Timestamp.now()});
      final docs = (await db.collection('violations').get()).docs;
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: AdminViolationsScreen(violations: Stream.value(docs)))));
      await settle(tester);
      expect(find.byKey(const ValueKey('violUser_customer1')), findsOneWidget);
      expect(find.text('Strikes: 3'), findsOneWidget);
      expect(find.textContaining('Suspended until'), findsOneWidget);
      expect(find.textContaining('call 98765'), findsOneWidget);
      expect(find.byKey(const ValueKey('lift_customer1')), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('lift_customer1')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      expect((await db.collection('users').doc('customer1').get()).data()!.containsKey('chatBlockedUntil'), isFalse);
    });
  });

  testWidgets('the booking screen never shows the driver\'s phone, only the name', (tester) async {
    final b = bk('in_transit');
    final withPhone = Booking.fromMap('B2', {'driverId': 'driver1', 'customerId': 'customer1', 'status': 'in_transit', 'driverName': 'Ramesh', 'driverPhone': '+919800000002', 'pickup': 'A', 'drop': 'B'});
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: BookingSummary(booking: withPhone, showDriver: true))))));
    expect(find.textContaining('9800000002'), findsNothing);
    expect(find.textContaining('Ramesh'), findsOneWidget);
    expect(b.driverPhone, '');
  });
}
