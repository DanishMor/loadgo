import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/l10n/payment_timeline_strings.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/ledger_entry.dart';
import 'package:transport_app/core/payments/payment_timeline.dart';
import 'package:transport_app/core/payments/payment_timeline_card.dart';
import 'package:transport_app/core/services/backend.dart';

import 'test_utils.dart';

Booking bk({String status = 'delivered', String pay = 'pending', int? paid}) => Booking.fromMap('b1', {
      'driverId': 'd1', 'customerId': 'c1', 'status': status, 'pickup': 'Delhi', 'drop': 'Jaipur', 'agreedFarePaise': 1000000,
      'paymentStatus': pay, 'paidAmountPaise': ?paid,
      'timeline': {if (status == 'delivered') 'delivered': Timestamp.fromDate(DateTime(2026, 10, 5, 18))},
    });

LedgerEntry line(String type, int paise) => LedgerEntry(id: 'b1_$type', driverId: 'd1', bookingId: 'b1', type: type, amountPaise: paise, createdAt: DateTime(2026, 10, 6, 10));

void main() {
  setUp(() {
    languageNotifier.value = AppLanguage.english;
  });

  group('PaymentTimeline.of', () {
    test('trip still running: nothing is done, next is finish the trip', () {
      final t = PaymentTimeline.of(bk(status: 'in_transit'));
      expect(t.steps.map((s) => s.done), [false, false, false, false]);
      expect(t.next, PaymentNext.finishTrip);
      expect(t.complete, isFalse);
    });

    test('delivered, nobody paid yet: waiting for the customer', () {
      final t = PaymentTimeline.of(bk());
      expect(t.steps.map((s) => s.done), [true, false, false, false]);
      expect(t.steps.first.at, DateTime(2026, 10, 5, 18));
      expect(t.next, PaymentNext.waitCustomer);
    });

    test('customer marked paid: the driver has to confirm; the amount is shown', () {
      final t = PaymentTimeline.of(bk(pay: 'customer_marked_paid', paid: 1000000));
      expect(t.steps.map((s) => s.done), [true, true, false, false]);
      expect(t.steps[1].paise, 1000000);
      expect(t.next, PaymentNext.confirmReceived);
    });

    test('confirmed: wallet step shows the earning minus the commission', () {
      final t = PaymentTimeline.of(bk(pay: 'driver_confirmed', paid: 1000000), earning: line('trip_earning', 1000000), commission: line('platform_commission', -50000));
      expect(t.steps.map((s) => s.done), [true, true, true, true]);
      expect(t.steps[3].paise, 950000);
      expect(t.steps[3].at, DateTime(2026, 10, 6, 10));
      expect(t.commissionPaise, 50000);
      expect(t.next, PaymentNext.nothing);
      expect(t.complete, isTrue);
    });

    test('confirmed but the ledger line is not readable yet: wallet step stays open', () {
      final t = PaymentTimeline.of(bk(pay: 'driver_confirmed', paid: 1000000));
      expect(t.steps.map((s) => s.done), [true, true, true, false]);
      expect(t.steps[3].paise, isNull);
    });

    test('every state has a message key in all languages', () {
      for (final n in PaymentNext.values) {
        expect(paymentTimelineStrings.containsKey('ptNext_${n.name}'), isTrue, reason: n.name);
      }
      for (final s in PaymentStep.values) {
        expect(paymentTimelineStrings.containsKey('ptStep_${s.name}'), isTrue, reason: s.name);
      }
    });
  });

  group('PaymentTimelineCard', () {
    late FakeFirebaseFirestore db;
    setUp(() {
      db = FakeFirebaseFirestore();
      Backend.useFakes(db: db, uid: () => 'd1');
    });

    Future<void> show(WidgetTester t, Booking b) async {
      t.view.physicalSize = const Size(800, 2000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(home: LanguageScope(notifier: languageNotifier, child: Scaffold(body: SingleChildScrollView(child: PaymentTimelineCard(booking: b))))));
      await settle(t);
    }

    testWidgets('waiting for the customer', (t) async {
      await show(t, bk());
      expect(find.text('When do I get my money?'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const ValueKey('ptNext'))).data, startsWith('Next: waiting for the customer'));
      expect(find.byKey(const ValueKey('ptCommission')), findsNothing);
    });

    testWidgets('confirmed: reads the ledger lines and shows the wallet amount and commission', (t) async {
      await t.runAsync(() async {
        await db.collection('ledger').doc('b1_trip_earning').set({'driverId': 'd1', 'bookingId': 'b1', 'type': 'trip_earning', 'amountPaise': 1000000, 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 6, 10))});
        await db.collection('ledger').doc('b1_platform_commission').set({'driverId': 'd1', 'bookingId': 'b1', 'type': 'platform_commission', 'amountPaise': -50000, 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 6, 10))});
      });
      await show(t, bk(pay: 'driver_confirmed', paid: 1000000));
      expect(find.textContaining('LoadGo commission kept'), findsOneWidget);
      expect(find.textContaining('9,500'), findsOneWidget, reason: 'net amount in the wallet step');
      expect(t.widget<Text>(find.byKey(const ValueKey('ptNext'))).data, startsWith('All done'));
    });

    testWidgets('a cancelled booking shows nothing', (t) async {
      await show(t, bk(status: 'cancelled'));
      expect(find.byKey(const ValueKey('paymentTimeline')), findsNothing);
    });
  });

  test('payment timeline strings: 12 languages, same placeholders', () {
    final ph = RegExp(r'\{(\w+)\}');
    for (final e in paymentTimelineStrings.entries) {
      expect(e.value.length, 12, reason: e.key);
      expect(e.value.every((s) => s.trim().isNotEmpty), isTrue, reason: e.key);
      final want = ph.allMatches(e.value[0]).map((m) => m[1]).toSet();
      for (var i = 1; i < 12; i++) {
        expect(ph.allMatches(e.value[i]).map((m) => m[1]).toSet(), want, reason: '${e.key}/$i');
      }
    }
  });
}
