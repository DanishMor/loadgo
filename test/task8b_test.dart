import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_fraud_cases_screen.dart';
import 'package:transport_app/admin/admin_lists.dart';
import 'package:transport_app/admin/admin_payouts_screen.dart';
import 'package:transport_app/core/enterprise/route_report.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/fraud_case.dart';
import 'package:transport_app/core/models/ledger_entry.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/payout.dart';
import 'package:transport_app/core/pricing/fare_calculator.dart';
import 'package:transport_app/core/services/admin_console_service.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/fraud_case_service.dart';
import 'package:transport_app/core/services/payout_service.dart';
import 'package:transport_app/core/services/pricing_service.dart';
import 'package:transport_app/core/services/support_config.dart';
import 'package:transport_app/core/support/support_screens.dart';
import 'package:transport_app/core/widgets/detention_card.dart';
import 'package:transport_app/driver/wallet_screen.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  String uid = 'd1';
  setUp(() {
    db = FakeFirebaseFirestore();
    uid = 'd1';
    Backend.useFakes(db: db, uid: () => uid);
    PricingService.reset();
    languageNotifier.value = AppLanguage.english;
  });

  Widget app(Widget w) => LanguageScope(notifier: languageNotifier, child: MaterialApp(home: w));

  group('P14 config audit trail', () {
    test('saving a config document writes who changed which keys', () async {
      uid = 'admin1';
      await db.collection('config').doc('pricing').set({'gstPercent': 5, 'platformFeePercent': 5, 'updatedAt': Timestamp.now()});
      await AdminConsoleService.writeConfig('pricing', {'gstPercent': 12, 'platformFeePercent': 5, 'newKey': 1});
      final events = (await db.collection('audit_events').get()).docs.map((d) => d.data()).toList();
      expect(events, hasLength(1));
      expect(events.single['type'], 'config_change');
      expect(events.single['actorId'], 'admin1');
      expect((events.single['data'] as Map)['changedKeys'], ['gstPercent', 'newKey']);
      expect((events.single['data'] as Map)['doc'], 'pricing');
      expect((await db.collection('config').doc('pricing').get()).data()!['gstPercent'], 12);
    });

    testWidgets('the audit screen lists events', (tester) async {
      await tester.runAsync(() async {
        uid = 'admin1';
        await AdminConsoleService.writeConfig('pricing', {'gstPercent': 18});
      });
      await tester.pumpWidget(app(const AdminAuditScreen()));
      await settle(tester);
      expect(find.textContaining('config_change'), findsOneWidget);
      expect(find.textContaining('changedKeys: gstPercent'), findsOneWidget);
    });
  });

  group('SAFE8 support number', () {
    test('only a plausible phone number is accepted', () {
      expect(SupportConfig.validPhone('+91 1800-123-4567'), isTrue);
      expect(SupportConfig.validPhone('18001234567'), isTrue);
      expect(SupportConfig.validPhone('call me'), isFalse);
      expect(SupportConfig.validPhone('123'), isFalse);
      expect(SupportConfig.fromMap({'phone': 'bad', 'hours': ' 9-6 '}).hasPhone, isFalse);
      expect(SupportConfig.fromMap({'phone': '+9118001234567', 'hours': ' 9-6 '}).hours, '9-6');
      expect(SupportConfig.fromMap(null).hasPhone, isFalse);
    });

    testWidgets('help screen shows a call button only when configured', (tester) async {
      await tester.pumpWidget(app(const SupportHomeScreen()));
      await settle(tester);
      expect(find.byKey(const ValueKey('callSupport')), findsNothing);
      await tester.runAsync(() => db.collection('config').doc('support').set({'phone': '+9118001234567', 'hours': 'Mon-Sat 9-6'}));
      await tester.pumpWidget(app(SupportHomeScreen(key: UniqueKey())));
      await settle(tester);
      expect(find.byKey(const ValueKey('callSupport')), findsOneWidget);
      expect(find.text('+9118001234567 · Mon-Sat 9-6'), findsOneWidget);
    });
  });

  test('N15 report by driver', () async {
    Load load(String id) => Load(id: id, shipperId: 'c', pickup: 'A', drop: 'B', cargoType: 'x', weight: 1, vehicleType: 'Mini', budget: null, pickupDate: null, notes: '', status: 'matched');
    Future<Booking> b(String id, String driver, String status, int fare) async {
      await db.collection('bookings').doc(id).set({'loadId': id, 'driverId': 'id_$driver', 'driverName': driver, 'status': status, 'agreedFarePaise': fare});
      return Booking.fromDoc(await db.collection('bookings').doc(id).get());
    }

    final r = RouteReport.from(
      [load('1'), load('2'), load('3'), load('4')],
      [await b('1', 'Ramesh', 'delivered', 100000), await b('2', 'Ramesh', 'in_transit', 5000), await b('3', 'Suresh', 'delivered', 70000)],
      const [],
    );
    expect(r.drivers.map((d) => d.driver), ['Ramesh', 'Suresh']);
    expect((r.drivers.first.trips, r.drivers.first.delivered, r.drivers.first.spendPaise), (2, 1, 100000));
    expect(r.toCsv(), contains('Ramesh,2,1,1000.00'));
  });

  group('D8 / PAY9 wallet balances and payouts', () {
    LedgerEntry line(String type, int paise) => LedgerEntry(id: '$type$paise', driverId: 'd1', bookingId: 'b', type: type, amountPaise: paise);
    Payout payout(int paise, String status) => Payout(id: '$paise$status', driverId: 'd1', amountPaise: paise, status: status);
    Future<Booking> booking(String id, String status, String pay, int fare) async {
      await db.collection('bookings').doc(id).set({'driverId': 'd1', 'status': status, 'paymentStatus': pay, 'agreedFarePaise': fare});
      return Booking.fromDoc(await db.collection('bookings').doc(id).get());
    }

    test('pending, available, requested and paid out', () async {
      final bal = WalletBalances.of(
        ledger: [line('trip_earning', 100000), line('platform_commission', -5000)],
        bookings: [
          await booking('a', 'delivered', 'pending', 40000),
          await booking('b', 'delivered', 'customer_marked_paid', 60000),
          await booking('c', 'delivered', 'driver_confirmed', 100000),
          await booking('d', 'in_transit', 'pending', 99999),
        ],
        payouts: [payout(20000, 'paid'), payout(10000, 'requested'), payout(7000, 'rejected')],
      );
      expect(bal.pending, 100000, reason: 'delivered but not confirmed');
      expect(bal.net, 95000);
      expect(bal.paidOut, 20000);
      expect(bal.requested, 10000);
      expect(bal.available, 65000);
      expect(const WalletBalances(pending: 0, net: 100, requested: 500, paidOut: 0).available, 0);
    });

    Future<void> confirmedTrip(int paise) async {
      await db.collection('ledger').doc('b1_trip_earning').set({'driverId': 'd1', 'bookingId': 'b1', 'type': 'trip_earning', 'amountPaise': paise, 'createdAt': Timestamp.now()});
      await db.collection('ledger').doc('b1_platform_commission').set({'driverId': 'd1', 'bookingId': 'b1', 'type': 'platform_commission', 'amountPaise': -(paise ~/ 20), 'createdAt': Timestamp.now()});
    }

    test('a request must be positive, within the balance, and only one at a time', () async {
      await confirmedTrip(100000); // net 95000
      await expectLater(PayoutService.request(50), throwsA(isA<PayoutException>().having((e) => e.reason, 'reason', 'amount')));
      await expectLater(PayoutService.request(95001), throwsA(isA<PayoutException>().having((e) => e.reason, 'reason', 'too_much')));
      final id = await PayoutService.request(60000);
      final d = (await db.collection('payouts').doc(id).get()).data()!;
      expect(d['status'], 'requested');
      expect(d['driverId'], 'd1');
      expect(d['amountPaise'], 60000);
      await expectLater(PayoutService.request(1000), throwsA(isA<PayoutException>().having((e) => e.reason, 'reason', 'open_request')));
      expect((await PayoutService.balances()).available, 35000);

      uid = 'admin1';
      await PayoutService.setStatus(id, Payout.paid);
      final p = (await db.collection('payouts').doc(id).get()).data()!;
      expect(p['status'], 'paid');
      expect(p['handledBy'], 'admin1');
      uid = 'd1';
      final after = await PayoutService.balances();
      expect((after.paidOut, after.requested, after.available), (60000, 0, 35000));
      await PayoutService.request(35000); // a new request is possible now
    });

    test('a rejected request gives the money back', () async {
      await confirmedTrip(100000);
      final id = await PayoutService.request(95000);
      uid = 'admin1';
      await PayoutService.setStatus(id, Payout.rejected);
      uid = 'd1';
      expect((await PayoutService.balances()).available, 95000);
    });

    testWidgets('wallet screen: figures, request dialog, and the waiting state', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => confirmedTrip(100000));
      await tester.pumpWidget(app(const WalletScreen()));
      await settle(tester);
      expect(find.byKey(const ValueKey('walletAvailable')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('walletAvailable'))).data, '₹ 950');
      await tester.tap(find.byKey(const ValueKey('requestPayout')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('payoutAmount')), '400');
      await tester.tap(find.byKey(const ValueKey('payoutSubmit')));
      await settle(tester);
      expect((await tester.runAsync(() => db.collection('payouts').get()))!.docs.single.data()['amountPaise'], 40000);
      expect(tester.widget<Text>(find.byKey(const ValueKey('walletAvailable'))).data, '₹ 550');
      expect(find.textContaining('waiting for LoadGo'), findsOneWidget);
    });

    testWidgets('admin screen marks a request paid', (tester) async {
      await tester.runAsync(() => db.collection('payouts').doc('p1').set({'driverId': 'd1', 'amountPaise': 5000, 'status': 'requested', 'createdAt': Timestamp.now()}));
      uid = 'admin1';
      await tester.pumpWidget(app(const AdminPayoutsScreen()));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('paidPayout_p1')));
      await settle(tester);
      expect((await tester.runAsync(() => db.collection('payouts').doc('p1').get()))!.data()!['status'], 'paid');
    });
  });

  group('F18 fraud cases', () {
    test('open, note, investigate, close with a decision (restricting the user)', () async {
      uid = 'admin1';
      await db.collection('users').doc('bad1').set({'role': 'driver'});
      final id = await FraudCaseService.open(userId: 'bad1', summary: 'Took payment off the app', reportId: 'r1');
      var c = FraudCase.fromDoc(id, (await db.collection('fraud_cases').doc(id).get()).data()!);
      expect(c.status, 'open');
      expect(c.reportIds, ['r1']);
      await FraudCaseService.addNote(id, 'Chat shows a UPI id');
      await FraudCaseService.setStatus(id, FraudCase.investigating);
      expect((await FraudCaseService.watchNotes(id).first).single.text, 'Chat shows a UPI id');
      expect((await FraudCaseService.watch(id).first)!.status, 'investigating');

      await FraudCaseService.close(id, userId: 'bad1', outcome: FraudCase.outcomeRestricted);
      c = FraudCase.fromDoc(id, (await db.collection('fraud_cases').doc(id).get()).data()!);
      expect(c.status, 'resolved');
      expect(c.outcome, 'restricted');
      expect(c.isClosed, isTrue);
      expect((await db.collection('users').doc('bad1').get()).data()!['riskTier'], 'restricted');
      expect((await db.collection('users').doc('bad1').get()).data()!['riskReason'], 'case $id');
    });

    test('no action dismisses the case without touching the user; bad input is refused', () async {
      uid = 'admin1';
      await db.collection('users').doc('u2').set({'role': 'driver'});
      final id = await FraudCaseService.open(userId: 'u2', summary: 'Looks fine after review');
      await FraudCaseService.close(id, userId: 'u2', outcome: FraudCase.outcomeNoAction, dismiss: true);
      expect((await db.collection('fraud_cases').doc(id).get()).data()!['status'], 'dismissed');
      expect((await db.collection('users').doc('u2').get()).data()!.containsKey('riskTier'), isFalse);
      await expectLater(FraudCaseService.open(userId: '', summary: 'x'), throwsArgumentError);
      await expectLater(FraudCaseService.open(userId: 'u', summary: 'ab'), throwsArgumentError);
      expect(() => FraudCaseService.addNote(id, '  '), throwsArgumentError);
      expect(() => FraudCaseService.setStatus(id, 'resolved'), throwsArgumentError);
      await expectLater(FraudCaseService.close(id, userId: 'u2', outcome: 'banished'), throwsArgumentError);
    });

    testWidgets('screens: create from the list, add a note, close', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      uid = 'admin1';
      await tester.pumpWidget(app(const AdminFraudCasesScreen()));
      await settle(tester);
      expect(find.text('No cases'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('newCase')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('caseUser')), 'bad9');
      await tester.enterText(find.byKey(const ValueKey('caseSummary')), 'Fake documents');
      await tester.tap(find.byKey(const ValueKey('caseCreate')));
      await settle(tester);
      expect(find.text('Fraud case'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('noteField')), 'Checked the licence');
      await tester.tap(find.byKey(const ValueKey('noteAdd')));
      await settle(tester);
      expect(find.text('Checked the licence'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('close_warned')));
      await tester.tap(find.byKey(const ValueKey('close_warned')));
      await settle(tester);
      final doc = (await tester.runAsync(() => db.collection('fraud_cases').get()))!.docs.single.data();
      expect((doc['status'], doc['outcome']), ('resolved', 'warned'));
    });

    testWidgets('a report can become a case', (tester) async {
      uid = 'admin1';
      await tester.runAsync(() => db.collection('reports').doc('r1').set({
            'reporterId': 'c1', 'reportedId': 'bad1', 'reason': 'fraud', 'details': 'asked for cash', 'status': 'open', 'createdAt': Timestamp.now(),
          }));
      await tester.pumpWidget(app(const AdminReportsScreen()));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('openCase_r1')));
      await settle(tester);
      final doc = (await tester.runAsync(() => db.collection('fraud_cases').get()))!.docs.single.data();
      expect(doc['userId'], 'bad1');
      expect(doc['reportIds'], ['r1']);
      expect(doc['summary'], 'fraud: asked for cash');
    });
  });

  group('P10 detention', () {
    test('model: minutes, running clock, caps', () {
      final d = Detention.fromMap({'loadingMinutes': 30, 'unloadingMinutes': 15, 'unloadingStartedAt': Timestamp.fromDate(DateTime(2026, 10, 8, 10))});
      expect(d.totalMinutes, 45);
      expect(d.minutesAt(DateTime(2026, 10, 8, 10, 20)), 65);
      expect(d.minutesAt(DateTime(2026, 10, 8, 10, 0, 30)), 46, reason: 'a started minute counts');
      expect(const Detention().isEmpty, isTrue);
      expect(Detention.fromMap(null).totalMinutes, 0);
    });

    test('charge: first hour free, then started hours at the waiting rate', () {
      const rule = PricingRule(baseFare: 1, perKm: 1, minimumFare: 1, waitingPerHour: 30000);
      expect(FareCalculator.detentionCharge(rule, 45), 0);
      expect(FareCalculator.detentionCharge(rule, 60), 0);
      expect(FareCalculator.detentionCharge(rule, 61), 30000);
      expect(FareCalculator.detentionCharge(rule, 120), 30000);
      expect(FareCalculator.detentionCharge(rule, 121), 60000);
      expect(FareCalculator.detentionCharge(rule, 100, freeMinutes: 30), 60000);
    });

    Future<Booking> loadingBooking({String status = 'loading'}) async {
      await db.collection('bookings').doc('b1').set({'driverId': 'd1', 'customerId': 'c1', 'status': status, 'vehicleType': '14ft', 'pickup': 'A', 'drop': 'B', 'timeline': {}});
      return Booking.fromDoc(await db.collection('bookings').doc('b1').get());
    }

    test('start and stop add the waited minutes to the current stage', () async {
      var b = await loadingBooking();
      await BookingService.startWaiting(b);
      b = Booking.fromDoc(await db.collection('bookings').doc('b1').get());
      expect(b.detention.loadingStartedAt, isNotNull);
      await BookingService.stopWaiting(b, now: b.detention.loadingStartedAt!.add(const Duration(minutes: 47, seconds: 10)));
      b = Booking.fromDoc(await db.collection('bookings').doc('b1').get());
      expect(b.detention.loadingMinutes, 48);
      expect(b.detention.loadingStartedAt, isNull);
      await BookingService.startWaiting(b);
      b = Booking.fromDoc(await db.collection('bookings').doc('b1').get());
      await BookingService.stopWaiting(b, now: b.detention.loadingStartedAt!.add(const Duration(minutes: 5)));
      expect(Booking.fromDoc(await db.collection('bookings').doc('b1').get()).detention.loadingMinutes, 53);
    });

    test('only the driver, and only while loading or unloading', () async {
      final b = await loadingBooking();
      uid = 'c1';
      await expectLater(BookingService.startWaiting(b), throwsStateError);
      uid = 'd1';
      final moving = await loadingBooking(status: 'in_transit');
      await expectLater(BookingService.startWaiting(moving), throwsStateError);
      await expectLater(BookingService.stopWaiting(b), throwsStateError, reason: 'clock is not running');
    });

    testWidgets('card: driver starts and stops; the customer sees the figures and charge', (tester) async {
      final b0 = (await tester.runAsync(loadingBooking))!;
      var shown = b0;
      await tester.pumpWidget(StatefulBuilder(builder: (context, set) => app(Scaffold(body: DetentionCard(booking: shown, isDriver: true)))));
      expect(find.byKey(const ValueKey('detentionToggle')), findsOneWidget);
      expect(find.text('Start waiting clock'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('detentionToggle')));
      await settle(tester);
      expect((await tester.runAsync(() => db.collection('bookings').doc('b1').get()))!.data()!['detention']['loadingStartedAt'], isNotNull);

      // customer view of a booking that has waiting time
      await tester.runAsync(() => db.collection('bookings').doc('b1').update({'detention': {'loadingMinutes': 125}}));
      shown = (await tester.runAsync(() async => Booking.fromDoc(await db.collection('bookings').doc('b1').get())))!;
      await tester.pumpWidget(app(Scaffold(body: DetentionCard(booking: shown, isDriver: false))));
      expect(find.text('Waited 125 min at loading and unloading'), findsOneWidget);
      expect(find.byKey(const ValueKey('detentionToggle')), findsNothing);
      expect(find.textContaining('Waiting charge: ₹'), findsOneWidget);
    });

    testWidgets('card is hidden when there is nothing to show', (tester) async {
      final b = (await tester.runAsync(() => loadingBooking(status: 'accepted')))!;
      await tester.pumpWidget(app(Scaffold(body: DetentionCard(booking: b, isDriver: true))));
      expect(find.byKey(const ValueKey('detentionCard')), findsNothing);
    });
  });
}
