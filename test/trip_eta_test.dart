import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/reminders/reminders.dart';
import 'package:transport_app/core/trip/trip_eta.dart';
import 'package:transport_app/core/widgets/booking_widgets.dart';
import 'package:transport_app/core/widgets/reminder_widgets.dart';
import 'package:transport_app/core/widgets/trip_eta_card.dart';


final t0 = DateTime(2026, 10, 5, 8, 0);

Booking trip({String status = 'in_transit', Map<String, DateTime>? timeline, String pickup = 'Pune', String drop = 'Delhi'}) => Booking(
      id: 'b1', loadId: 'b1', driverId: 'd', vehicleId: 'v', customerId: 'c', status: status, pickup: pickup, drop: drop, cargoType: 'x', weight: 1,
      vehicleType: '20ft', budget: null, pickupDate: null, notes: '', vehicleNumber: 'MH12AB1', driverName: 'D', driverPhone: '1',
      timeline: timeline ??
          {
            'accepted': t0,
            'driver_arriving': t0.add(const Duration(minutes: 20)),
            'loading': t0.add(const Duration(minutes: 50)),
            'picked_up': t0.add(const Duration(hours: 2)),
            'in_transit': t0.add(const Duration(hours: 2, minutes: 5)),
          },
    );

void main() {
  setUp(() => languageNotifier.value = AppLanguage.english);

  test('travel time is distance at 40 km/h; ETA counts from pickup', () {
    expect(TripEta.travelTime(40), const Duration(hours: 1));
    expect(TripEta.travelTime(1400), const Duration(hours: 35));
    final b = trip();
    expect(TripEta.eta(b, 400), t0.add(const Duration(hours: 12))); // picked up 2 h after t0, plus 10 h on the road
    expect(TripEta.eta(trip(timeline: {'accepted': t0}, status: 'accepted'), 400), isNull);
    expect(TripEta.eta(b, null), isNull);
  });

  test('delay needs more than the grace period, only on the road', () {
    final b = trip();
    final eta = TripEta.eta(b, 400)!; // 10:00 + 10 h
    expect(TripEta.delayMinutes(b, eta, eta.add(const Duration(minutes: 30))), isNull);
    expect(TripEta.delayMinutes(b, eta, eta.add(const Duration(minutes: 60))), isNull);
    expect(TripEta.delayMinutes(b, eta, eta.add(const Duration(minutes: 95))), 95);
    expect(TripEta.delayMinutes(trip(status: 'delivered'), eta, eta.add(const Duration(hours: 5))), isNull);
    expect(TripEta.delayMinutes(trip(status: 'loading'), eta, eta.add(const Duration(hours: 5))), isNull);
    expect(TripEta.delayMinutes(b, null, eta), isNull);
  });

  test('step durations and road time', () {
    final b = trip(status: 'delivered', timeline: {
      'accepted': t0,
      'driver_arriving': t0.add(const Duration(minutes: 20)),
      'picked_up': t0.add(const Duration(hours: 2)),
      'delivered': t0.add(const Duration(hours: 14)),
    });
    final steps = TripEta.steps(b);
    expect(steps.map((s) => s.status), ['accepted', 'driver_arriving', 'picked_up', 'delivered']);
    expect(steps.map((s) => s.sincePrevious), [null, const Duration(minutes: 20), const Duration(hours: 1, minutes: 40), const Duration(hours: 12)]);
    expect(TripEta.roadTime(b), const Duration(hours: 12));
    expect(TripEta.roadTime(trip()), isNull);
  });

  test('the delay reminder shows for both roles and names the route', () {
    final b = trip();
    final eta = TripEta.eta(b, 400)!;
    List<Reminder> run(DateTime now, {bool driver = false}) =>
        ReminderEngine.compute(ReminderInput(now: now, isDriver: driver, bookings: [b], etaOf: (x) => eta));
    expect(run(eta.add(const Duration(minutes: 30))).where((r) => r.kind == ReminderKind.tripDelayed), isEmpty);
    final r = run(eta.add(const Duration(minutes: 150))).singleWhere((r) => r.kind == ReminderKind.tripDelayed);
    expect((r.args['route'], r.args['minutes'], r.relatedId, r.priority), ('Pune → Delhi', 150, 'b1', 0));
    expect(run(eta.add(const Duration(minutes: 150)), driver: true).any((r) => r.kind == ReminderKind.tripDelayed), isTrue);
    expect(ReminderEngine.compute(ReminderInput(now: eta.add(const Duration(hours: 9)), isDriver: false, bookings: [b])).any((r) => r.kind == ReminderKind.tripDelayed), isFalse,
        reason: 'no ETA function, no alert');
  });

  testWidgets('card: trip time before pickup, ETA on the road, late warning, took time after delivery', (tester) async {
    Future<String?> line(Booking b, DateTime now) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: TripEtaCard(booking: b, clock: () => now))));
      await tester.pump();
      final f = find.byKey(const ValueKey('tripEtaLine'));
      return f.evaluate().isEmpty ? null : (tester.widget(f) as Text).data;
    }

    final accepted = trip(status: 'accepted', timeline: {'accepted': t0});
    expect(await line(accepted, t0), startsWith('Estimated trip time: '));
    final onRoad = trip();
    final onTime = await line(onRoad, t0.add(const Duration(hours: 5)));
    expect(onTime, startsWith('Estimated arrival: '));
    // Pune -> Delhi is far more than 400 km, so be late by waiting a lot longer than any estimate
    final late = await line(onRoad, t0.add(const Duration(days: 5)));
    expect(late, contains('behind the estimate'));
    final done = trip(status: 'delivered', timeline: {'picked_up': t0, 'delivered': t0.add(const Duration(hours: 13, minutes: 20))});
    expect(await line(done, t0.add(const Duration(days: 6))), 'Trip took 13 h 20 min on the road');
    expect(await line(trip(pickup: 'Nowhereville', drop: 'Delhi'), t0), isNull, reason: 'unknown place: no estimate');
    expect(await line(trip(status: 'cancelled'), t0), isNull);
  });

  testWidgets('timeline shows how long each step took; reminder text is translated', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: BookingTimeline(booking: trip())))));
    expect(find.textContaining('+20 min'), findsOneWidget);
    expect(find.textContaining('+1 h 10 min'), findsOneWidget);
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    expect(reminderText(ctx, const Reminder(kind: ReminderKind.tripDelayed, id: 'x', args: {'route': 'A → B', 'minutes': 130}, priority: 0)), 'A → B: running about 2 h 10 min behind the estimate');
  });
}
