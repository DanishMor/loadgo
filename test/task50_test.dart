import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_feedback_screen.dart';
import 'package:transport_app/core/claims/declared_value_line.dart';
import 'package:transport_app/core/constants/cancel_reasons.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/l10n/feedback_cancel_strings.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/reminders/reminders.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/feedback_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/rating_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/core/settings/feedback_screen.dart';
import 'package:transport_app/core/settings/help_screen.dart';
import 'package:transport_app/core/widgets/cancel_reason_picker.dart';
import 'package:transport_app/core/widgets/reminder_widgets.dart';
import 'package:transport_app/customer/cancel_scheduled_button.dart';
import 'package:transport_app/customer/my_loads_view.dart';
import 'package:transport_app/customer/post_load_screen.dart';
import 'package:transport_app/driver/driver_trip_screen.dart';

import 'test_utils.dart';

void tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Widget host(Widget child) => MaterialApp(home: LanguageScope(notifier: languageNotifier, child: child));

void main() {
  late FakeFirebaseFirestore db;
  String? uid;

  setUp(() {
    languageNotifier.value = AppLanguage.english;
    db = FakeFirebaseFirestore();
    uid = 'customer1';
    Backend.useFakes(db: db, uid: () => uid);
    FeedbackService.resetGuard();
  });

  Future<String> post({int? declared, DateTime? at}) => LoadService.post(
        pickup: 'Delhi',
        drop: 'Mumbai',
        cargoType: 'FMCG',
        weight: 8,
        vehicleType: '20ft',
        budget: 25000,
        pickupDate: at ?? DateTime(2026, 10, 5),
        scheduledAt: at,
        declaredValuePaise: declared,
        notes: '',
      );

  Future<String> accepted({DateTime? at}) async {
    final loadId = await post(at: at);
    uid = 'driver1';
    await VehicleService.add(number: 'MH12AB1234', type: '20ft', capacity: 10, rcNumber: 'RC1');
    final id = await BookingService.accept(loadId: loadId, vehicle: (await VehicleService.fetchMyActive()).single);
    uid = 'customer1';
    return id;
  }

  group('CancelReasons', () {
    test('lists, validity and keys', () {
      expect(CancelReasons.customer, hasLength(6));
      expect(CancelReasons.driver, hasLength(6));
      expect(CancelReasons.forRole('driver'), CancelReasons.driver);
      expect(CancelReasons.forRole('customer'), CancelReasons.customer);
      expect(CancelReasons.valid('customer', null), isTrue);
      expect(CancelReasons.valid('customer', 'price_high'), isTrue);
      expect(CancelReasons.valid('customer', 'vehicle_problem'), isFalse);
      expect(CancelReasons.valid('driver', 'vehicle_problem'), isTrue);
      expect(CancelReasons.valid('driver', 'price_high'), isFalse);
      expect(CancelReasons.valid('driver', 'other'), isTrue);
      expect(CancelReasons.labelKey('other'), 'cr_other');
    });

    test('every code has a translation key', () {
      for (final c in {...CancelReasons.customer, ...CancelReasons.driver}) {
        expect(feedbackCancelStrings.containsKey(CancelReasons.labelKey(c)), isTrue, reason: c);
      }
    });
  });

  group('services keep the reason', () {
    test('a customer cancelling an open load', () async {
      final id = await post();
      await LoadService.cancel(id, reason: 'driver_delay');
      final d = (await db.collection('loads').doc(id).get()).data()!;
      expect(d['cancelled'], isTrue);
      expect(d['cancelReason'], 'driver_delay');
      expect(Load.fromDoc(await db.collection('loads').doc(id).get()).cancelReason, 'driver_delay');
      final audit = (await db.collection('audit_events').where('type', isEqualTo: 'cancel').get()).docs.single.data();
      expect((audit['data'] as Map)['reason'], 'driver_delay');
    });

    test('no reason means no reason field', () async {
      final id = await post();
      await LoadService.cancel(id);
      expect((await db.collection('loads').doc(id).get()).data()!.containsKey('cancelReason'), isFalse);
    });

    test('a wrong or driver-only reason is refused before anything is written', () async {
      final id = await post();
      expect(() => LoadService.cancel(id, reason: 'vehicle_problem'), throwsArgumentError);
      expect(() => LoadService.cancel(id, reason: 'whatever'), throwsArgumentError);
      expect((await db.collection('loads').doc(id).get())['status'], LoadStatus.open);
    });

    test('a driver cancelling a booking', () async {
      final id = await accepted();
      uid = 'driver1';
      await BookingService.cancelByDriver(id, reason: 'customer_unreachable');
      final snap = await db.collection('bookings').doc(id).get();
      expect((snap.data()!['cancellation'] as Map)['reason'], 'customer_unreachable');
      expect(Booking.fromDoc(snap).cancellation!.reason, 'customer_unreachable');
      expect(Booking.fromDoc(snap).cancellation!.by, 'driver');
    });

    test('a driver cancel without a reason, and with a customer reason', () async {
      final id = await accepted();
      uid = 'driver1';
      expect(() => BookingService.cancelByDriver(id, reason: 'price_high'), throwsArgumentError);
      await BookingService.cancelByDriver(id);
      final c = (await db.collection('bookings').doc(id).get()).data()!['cancellation'] as Map;
      expect(c.containsKey('reason'), isFalse);
      expect(Booking.fromDoc(await db.collection('bookings').doc(id).get()).cancellation!.reason, isNull);
    });

    test('a customer cancelling an advance booking', () async {
      final id = await accepted(at: DateTime.now().add(const Duration(days: 2)));
      expect(() => BookingService.cancelScheduledByCustomer(id, reason: 'vehicle_problem'), throwsArgumentError);
      await BookingService.cancelScheduledByCustomer(id, reason: 'plan_changed');
      final c = (await db.collection('bookings').doc(id).get()).data()!['cancellation'] as Map;
      expect(c['by'], 'customer');
      expect(c['reason'], 'plan_changed');
    });
  });

  group('CancelReasonPicker', () {
    testWidgets('shows the role\'s reasons; tapping selects, tapping again clears', (t) async {
      final picked = <String?>[];
      await t.pumpWidget(host(Scaffold(body: SingleChildScrollView(child: CancelReasonPicker(by: 'customer', onChanged: picked.add)))));
      expect(find.text('Why are you cancelling? (optional)'), findsOneWidget);
      expect(find.byKey(const ValueKey('cancelReason_price_high')), findsOneWidget);
      expect(find.byKey(const ValueKey('cancelReason_vehicle_problem')), findsNothing);
      await t.tap(find.byKey(const ValueKey('cancelReason_price_high')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('cancelReason_driver_delay')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('cancelReason_driver_delay')));
      await t.pump();
      expect(picked, ['price_high', 'driver_delay', null]);
    });

    testWidgets('a driver sees driver reasons', (t) async {
      await t.pumpWidget(host(Scaffold(body: SingleChildScrollView(child: CancelReasonPicker(by: 'driver', onChanged: (_) {})))));
      expect(find.byKey(const ValueKey('cancelReason_vehicle_problem')), findsOneWidget);
      expect(find.byKey(const ValueKey('cancelReason_price_high')), findsNothing);
    });
  });

  group('cancel dialogs save the chosen reason', () {
    testWidgets('My Loads', (t) async {
      late String id;
      await t.runAsync(() async => id = await post());
      await t.pumpWidget(host(Scaffold(body: MyLoadsView(onPostLoad: () {}, onOpenBooking: (_) {}))));
      await settle(t);
      await t.tap(find.text('Cancel load'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('cancelReason_price_high')));
      await t.pump();
      await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
      await settle(t);
      expect((await db.collection('loads').doc(id).get())['cancelReason'], 'price_high');
    });

    testWidgets('My Loads: no choice, no reason', (t) async {
      late String id;
      await t.runAsync(() async => id = await post());
      await t.pumpWidget(host(Scaffold(body: MyLoadsView(onPostLoad: () {}, onOpenBooking: (_) {}))));
      await settle(t);
      await t.tap(find.text('Cancel load'));
      await t.pumpAndSettle();
      await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
      await settle(t);
      expect((await db.collection('loads').doc(id).get()).data()!.containsKey('cancelReason'), isFalse);
    });

    testWidgets('driver trip screen', (t) async {
      t.view.physicalSize = const Size(800, 2800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      late String id;
      await t.runAsync(() async => id = await accepted());
      uid = 'driver1';
      await t.pumpWidget(MaterialApp(home: DriverTripScreen(bookingId: id)));
      await settle(t);
      await t.ensureVisible(find.text('Cancel booking'));
      await t.tap(find.text('Cancel booking'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('cancelReason_vehicle_problem')));
      await t.pump();
      await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
      await settle(t);
      final c = (await db.collection('bookings').doc(id).get()).data()!['cancellation'] as Map;
      expect(c['reason'], 'vehicle_problem');
    });

    testWidgets('customer cancelling an advance booking', (t) async {
      late Booking b;
      await t.runAsync(() async {
        final id = await accepted(at: DateTime.now().add(const Duration(days: 2)));
        b = Booking.fromDoc(await db.collection('bookings').doc(id).get());
      });
      await t.pumpWidget(host(Scaffold(body: CancelScheduledButton(booking: b))));
      await t.tap(find.byKey(const ValueKey('cancelScheduled')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('cancelReason_found_other')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('cancelScheduledConfirm')));
      await settle(t);
      final c = (await db.collection('bookings').doc(b.id).get()).data()!['cancellation'] as Map;
      expect(c['reason'], 'found_other');
    });
  });

  group('declared goods value', () {
    test('stored in paise, missing for none or zero, limits enforced', () async {
      final id = await post(declared: 5000000);
      final snap = await db.collection('loads').doc(id).get();
      expect(snap['declaredValuePaise'], 5000000);
      expect(Load.fromDoc(snap).declaredValuePaise, 5000000);
      expect((await db.collection('loads').doc(await post()).get()).data()!.containsKey('declaredValuePaise'), isFalse);
      expect((await db.collection('loads').doc(await post(declared: 0)).get()).data()!.containsKey('declaredValuePaise'), isFalse);
      await post(declared: CancelReasons.maxDeclaredValuePaise);
      expect(() => post(declared: CancelReasons.maxDeclaredValuePaise + 1), throwsArgumentError);
      expect(() => post(declared: -1), throwsArgumentError);
    });

    testWidgets('Post Load has the field and repost fills it', (t) async {
      t.view.physicalSize = const Size(800, 3000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      late Load l;
      await t.runAsync(() async {
        final id = await post(declared: 150000);
        l = Load.fromDoc(await db.collection('loads').doc(id).get());
      });
      await t.pumpWidget(host(PostLoadScreen(repostFrom: l)));
      await settle(t);
      await t.ensureVisible(find.byKey(const ValueKey('declaredValue')));
      expect(find.byKey(const ValueKey('declaredValue')), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '1500'), findsOneWidget);
      expect(find.text('Value of goods in ₹ (optional)'), findsOneWidget);
    });

    testWidgets('the claim line shows the value, "not declared", or nothing', (t) async {
      late String withValue, without, bookingId;
      await t.runAsync(() async {
        withValue = await post(declared: 250000);
        without = await post();
        await db.collection('bookings').doc('bk1').set({'loadId': withValue});
        bookingId = 'bk1';
      });
      await t.pumpWidget(host(Scaffold(body: DeclaredValueLine(loadId: withValue))));
      await settle(t);
      expect(find.text('Declared goods value: ₹ 2,500'), findsOneWidget);
      await t.pumpWidget(host(Scaffold(body: DeclaredValueLine(loadId: without))));
      await settle(t);
      expect(find.text('Goods value was not declared'), findsOneWidget);
      await t.pumpWidget(host(Scaffold(body: DeclaredValueLine(bookingId: bookingId))));
      await settle(t);
      expect(find.text('Declared goods value: ₹ 2,500'), findsOneWidget);
      await t.pumpWidget(host(const Scaffold(body: DeclaredValueLine(loadId: 'missing'))));
      await settle(t);
      expect(find.byKey(const ValueKey('declaredValueLine')), findsNothing);
      await t.pumpWidget(host(const Scaffold(body: DeclaredValueLine())));
      await settle(t);
      expect(find.byKey(const ValueKey('declaredValueLine')), findsNothing);
    });
  });

  group('feedback', () {
    test('send validates and stores the sender, role, version and server time', () async {
      await db.collection('users').doc('customer1').set({'role': 'customer'});
      await FeedbackService.send(rating: 4, category: 'idea', text: '  add dark mode  ');
      final d = (await db.collection('feedback').get()).docs.single.data();
      expect(d['userId'], 'customer1');
      expect(d['role'], 'customer');
      expect(d['rating'], 4);
      expect(d['category'], 'idea');
      expect(d['text'], 'add dark mode');
      expect(d['appVersion'], '1.0.0+1');
      expect(d['createdAt'], isNotNull);
    });

    test('role comes from the profile (driver, fleet) with a customer default', () async {
      await db.collection('users').doc('d1').set({'role': 'driver'});
      await db.collection('users').doc('f1').set({'selectedRole': 'fleet'});
      uid = 'd1';
      await FeedbackService.send(rating: 5, category: 'app');
      FeedbackService.resetGuard();
      uid = 'f1';
      await FeedbackService.send(rating: 5, category: 'app');
      FeedbackService.resetGuard();
      uid = 'nobody';
      await FeedbackService.send(rating: 5, category: 'app');
      final roles = (await db.collection('feedback').get()).docs.map((d) => '${d['userId']}:${d['role']}').toSet();
      expect(roles, {'d1:driver', 'f1:fleet', 'nobody:customer'});
    });

    test('bad input is refused', () async {
      expect(() => FeedbackService.send(rating: 0, category: 'app'), throwsArgumentError);
      expect(() => FeedbackService.send(rating: 6, category: 'app'), throwsArgumentError);
      expect(() => FeedbackService.send(rating: 3, category: 'rant'), throwsArgumentError);
      expect(() => FeedbackService.send(rating: 3, category: 'app', text: 'a' * 501), throwsArgumentError);
      expect((await db.collection('feedback').get()).docs, isEmpty);
    });

    test('the 30 second guard', () async {
      var now = DateTime(2026, 10, 7, 10);
      await FeedbackService.send(rating: 5, category: 'app', now: () => now);
      now = now.add(const Duration(seconds: 10));
      expect(() => FeedbackService.send(rating: 5, category: 'app', now: () => now), throwsA(isA<FeedbackTooSoonException>()));
      now = now.add(const Duration(seconds: 25));
      await FeedbackService.send(rating: 5, category: 'app', now: () => now);
      expect((await db.collection('feedback').get()).docs.length, 2);
    });

    testWidgets('screen: stars are needed, then it sends and closes', (t) async {
      tall(t);
      await t.pumpWidget(host(Builder(
        builder: (c) => Scaffold(body: TextButton(key: const ValueKey('go'), onPressed: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => const FeedbackScreen())), child: const Text('go'))),
      )));
      await t.tap(find.byKey(const ValueKey('go')));
      await t.pumpAndSettle();
      await t.tap(find.text('Send'));
      await t.pumpAndSettle();
      expect(find.text('Please choose the stars first'), findsOneWidget);
      expect((await db.collection('feedback').get()).docs, isEmpty);
      await t.pump(const Duration(seconds: 5)); // snack bars queue: let the first one go
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('fbStar_4')));
      await t.tap(find.byKey(const ValueKey('fbCat_payment')));
      await t.enterText(find.byKey(const ValueKey('fbText')), 'UPI link was slow');
      await t.tap(find.text('Send'));
      await settle(t);
      final d = (await t.runAsync(() => db.collection('feedback').get()))!.docs.single.data();
      expect(d['rating'], 4);
      expect(d['category'], 'payment');
      expect(d['text'], 'UPI link was slow');
      expect(find.byType(FeedbackScreen), findsNothing);
      expect(find.text('Thank you for your feedback'), findsOneWidget);
    });

    testWidgets('screen: a second send right away is told to wait', (t) async {
      tall(t);
      await t.runAsync(() => FeedbackService.send(rating: 5, category: 'app'));
      await t.pumpWidget(host(const FeedbackScreen()));
      await t.tap(find.byKey(const ValueKey('fbStar_3')));
      await t.tap(find.text('Send'));
      await settle(t);
      expect(find.text('You just sent feedback. Please wait a little.'), findsOneWidget);
      expect((await t.runAsync(() => db.collection('feedback').get()))!.docs.length, 1);
    });

    testWidgets('Help has the feedback entry', (t) async {
      await t.pumpWidget(host(const HelpScreen()));
      // the list builds its rows lazily: scroll until the entry exists
      for (var n = 0; n < 40 && find.byKey(const ValueKey('helpFeedback')).evaluate().isEmpty; n++) {
        await t.drag(find.byType(ListView).first, const Offset(0, -300));
        await t.pump();
      }
      await t.ensureVisible(find.byKey(const ValueKey('helpFeedback')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('helpFeedback')));
      await t.pumpAndSettle();
      expect(find.byType(FeedbackScreen), findsOneWidget);
    });

    testWidgets('admin list shows stars, category, text and sender', (t) async {
      await db.collection('feedback').add({
        'userId': 'u1', 'role': 'driver', 'rating': 2, 'category': 'pricing', 'text': 'Too costly', 'appVersion': '1.0.0+1', 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 6)),
      });
      await t.pumpWidget(host(const AdminFeedbackScreen()));
      await settle(t);
      expect(find.text('Price'), findsOneWidget);
      expect(find.text('Too costly'), findsOneWidget);
      expect(find.textContaining('driver · 1.0.0+1'), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsNWidgets(2));
    });

    testWidgets('admin list: empty state', (t) async {
      await t.pumpWidget(host(const AdminFeedbackScreen()));
      await settle(t);
      expect(find.text('No feedback yet'), findsOneWidget);
    });
  });

  group('rating reminder', () {
    final now = DateTime(2026, 10, 10, 12);
    Booking b(String id, {String status = 'delivered', DateTime? deliveredAt, String pickup = 'Delhi', String drop = 'Jaipur'}) => Booking(
          id: id, loadId: 'l$id', driverId: 'd1', vehicleId: 'v1', customerId: 'c1', status: status, pickup: pickup, drop: drop, cargoType: 'x', weight: 1,
          vehicleType: '14ft', budget: 1000, pickupDate: DateTime(2026, 10, 1), notes: '', vehicleNumber: 'X', driverName: 'D', driverPhone: '1',
          timeline: {'delivered': ?deliveredAt},
        );
    List<Reminder> rem(List<Booking> bookings, Set<String>? rated, {bool driver = false}) =>
        ReminderEngine.compute(ReminderInput(now: now, isDriver: driver, bookings: bookings, ratedBookingIds: rated)).where((r) => r.kind == ReminderKind.rateTrip).toList();

    test('due after 24 hours, not before; stops after 14 days', () {
      expect(rem([b('a', deliveredAt: now.subtract(const Duration(hours: 23, minutes: 59)))], {}), isEmpty);
      expect(rem([b('a', deliveredAt: now.subtract(const Duration(hours: 24)))], {}), hasLength(1));
      expect(rem([b('a', deliveredAt: now.subtract(const Duration(days: 14)))], {}), hasLength(1));
      expect(rem([b('a', deliveredAt: now.subtract(const Duration(days: 14, minutes: 1)))], {}), isEmpty);
    });

    test('rated trips, other statuses and an unknown rating list make no reminder', () {
      final old = now.subtract(const Duration(days: 3));
      expect(rem([b('a', deliveredAt: old)], {'a'}), isEmpty);
      expect(rem([b('a', status: 'in_transit', deliveredAt: old), b('c', status: 'cancelled', deliveredAt: old)], {}), isEmpty);
      expect(rem([b('a', deliveredAt: old)], null), isEmpty, reason: 'ratings not loaded yet');
      expect(rem([b('a')], {}), isEmpty, reason: 'no delivery time known');
    });

    test('one reminder: the newest unrated trip and a count', () {
      final list = [
        b('old', deliveredAt: now.subtract(const Duration(days: 5)), pickup: 'Agra', drop: 'Noida'),
        b('new', deliveredAt: now.subtract(const Duration(days: 2)), pickup: 'Pune', drop: 'Mumbai'),
        b('done', deliveredAt: now.subtract(const Duration(days: 3))),
      ];
      final r = rem(list, {'done'}).single;
      expect(r.relatedId, 'new');
      expect(r.args['n'], 2);
      expect(r.args['route'], 'Pune → Mumbai');
      expect(r.id, 'rate_new');
      expect(r.priority, 3);
    });

    test('works for drivers too', () {
      expect(rem([b('a', deliveredAt: now.subtract(const Duration(days: 2)))], {}, driver: true), hasLength(1));
    });

    testWidgets('the text is singular or plural and the icon is a star', (t) async {
      late BuildContext ctx;
      await t.pumpWidget(host(Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })));
      const one = Reminder(kind: ReminderKind.rateTrip, id: 'r', args: {'n': 1, 'route': 'A → B'}, priority: 3);
      const many = Reminder(kind: ReminderKind.rateTrip, id: 'r', args: {'n': 3, 'route': 'A → B'}, priority: 3);
      expect(reminderText(ctx, one), 'Rate your finished trip A → B');
      expect(reminderText(ctx, many), '3 finished trips are waiting for your rating');
      expect(reminderIcon(ReminderKind.rateTrip), Icons.star_outline_rounded);
    });

    test('RatingService lists the bookings I rated', () async {
      await db.collection('ratings').doc('b1_customer1').set({'bookingId': 'b1', 'raterId': 'customer1', 'ratedId': 'd1', 'stars': 5});
      await db.collection('ratings').doc('b2_customer1').set({'bookingId': 'b2', 'raterId': 'customer1', 'ratedId': 'd1', 'stars': 4});
      await db.collection('ratings').doc('b3_other').set({'bookingId': 'b3', 'raterId': 'other', 'ratedId': 'd1', 'stars': 4});
      expect(await RatingService.watchGivenBookingIds().first, {'b1', 'b2'});
      uid = null;
      expect(await RatingService.watchGivenBookingIds().first, isEmpty);
    });
  });

  test('every new string has 12 non-empty languages and the same placeholders', () {
    final ph = RegExp(r'\{(\w+)\}');
    for (final e in feedbackCancelStrings.entries) {
      expect(e.value.length, 12, reason: e.key);
      expect(e.value.every((s) => s.trim().isNotEmpty), isTrue, reason: e.key);
      final want = ph.allMatches(e.value[0]).map((m) => m[1]).toSet();
      for (var i = 1; i < 12; i++) {
        expect(ph.allMatches(e.value[i]).map((m) => m[1]).toSet(), want, reason: '${e.key}/$i');
      }
    }
  });
}
