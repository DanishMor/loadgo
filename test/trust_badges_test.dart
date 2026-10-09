import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/trust/trust_badges.dart';
import 'package:transport_app/core/trust/trust_badges_card.dart';

/// MASTER-6 Task 36: trust badges.
void main() {
  final day = DateTime(2026, 10, 5);
  Booking b(String id, {String status = 'delivered', String customer = 'c1', DateTime? pickedAt, DateTime? sched, String? cancelBy, String driver = 'd1'}) => Booking.fromMap(id, {
        'driverId': driver,
        'customerId': customer,
        'status': status,
        'pickupDate': Timestamp.fromDate(day),
        'scheduledAt': ?(sched == null ? null : Timestamp.fromDate(sched)),
        'timeline': {'picked_up': ?(pickedAt == null ? null : Timestamp.fromDate(pickedAt))},
        if (cancelBy != null) 'cancellation': {'by': cancelBy, 'chargePaise': 0},
      });

  test('on time: by the end of the pickup date, or within an hour of the scheduled time', () {
    expect(TrustBadges.onTime(b('1', pickedAt: day.add(const Duration(hours: 23)))), isTrue);
    expect(TrustBadges.onTime(b('2', pickedAt: day.add(const Duration(days: 1, minutes: 1)))), isFalse);
    expect(TrustBadges.onTime(b('3', sched: day.add(const Duration(hours: 9)), pickedAt: day.add(const Duration(hours: 9, minutes: 59)))), isTrue);
    expect(TrustBadges.onTime(b('4', sched: day.add(const Duration(hours: 9)), pickedAt: day.add(const Duration(hours: 10, minutes: 1)))), isFalse);
    expect(TrustBadges.onTime(b('5')), isNull);
  });

  test('numbers count only my trips; completion ignores customer cancels; repeat needs two delivered trips', () {
    final list = [
      for (var i = 0; i < 4; i++) b('d$i', customer: 'c1', pickedAt: day.add(const Duration(hours: 8))),
      b('late', customer: 'c2', pickedAt: day.add(const Duration(days: 2))),
      b('mine', status: 'cancelled', cancelBy: 'driver'),
      b('theirs', status: 'cancelled', cancelBy: 'customer'),
      b('other', driver: 'd2'),
    ];
    final t = TrustBadges.compute(list, 'd1');
    expect((t.delivered, t.finished), (5, 6));
    expect(t.completionPercent, 83);
    expect((t.onTimeKnown, t.onTimePercent), (5, 80));
    expect(t.repeatCustomers, 1);
    expect(t.isNew, isFalse);
    expect(TrustBadges.compute([b('x')], 'd1').isNew, isTrue);
    expect(TrustBadges.compute(const [], 'd1').finished, 0);
  });

  testWidgets('the card says "New" with few trips and shows chips after five', (tester) async {
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'd1');
    languageNotifier.value = AppLanguage.english;
    Future<void> show(List<Booking> l) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(home: Scaffold(body: TrustBadgesCard(bookings: Stream.value(l))))));
      await tester.pump();
      await tester.pump();
    }

    await show(const []);
    expect(find.byKey(const ValueKey('trustCard')), findsNothing);
    await show([b('1', pickedAt: day.add(const Duration(hours: 8)))]);
    expect(find.byKey(const ValueKey('badge_new')), findsOneWidget);
    expect(find.text('New driver: 4 more finished trips and your numbers show here.'), findsOneWidget);
    await show([for (var i = 0; i < 5; i++) b('$i', pickedAt: day.add(const Duration(hours: 8)))]);
    expect(find.text('100% picked up on time'), findsOneWidget);
    expect(find.text('100% trips completed'), findsOneWidget);
    expect(find.byKey(const ValueKey('badge_repeat')), findsOneWidget);
  });
}
