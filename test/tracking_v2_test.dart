import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/customer/booking_tracking_screen.dart';
import 'package:transport_app/core/bilty/lr_form_screen.dart';
import 'package:transport_app/customer/v2/booking_wizard_screen.dart';
import 'package:transport_app/customer/v2/tracking_v2_screen.dart';

/// U21: the customer's trip page in the new app.
void main() {
  late FakeFirebaseFirestore db;
  String? uid;
  late String id;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => uid);
    FeaturesService.reset();
    languageNotifier.value = AppLanguage.english;
    uid = 'customer1';
    final loadId = await LoadService.post(pickup: 'Delhi', drop: 'Mumbai', cargoType: 'FMCG', weight: 8, vehicleType: '20ft', budget: null, pickupDate: DateTime(2030, 10, 5), notes: '');
    uid = 'driver1';
    await db.collection('users').doc('driver1').set({'driverName': 'Ramesh', 'phone': '+919800000000'});
    await VehicleService.add(number: 'MH12AB1234', type: '20ft', capacity: 10, rcNumber: 'RC1');
    id = await BookingService.accept(loadId: loadId, vehicle: (await VehicleService.fetchMyActive()).single);
    uid = 'customer1';
  });
  tearDown(FeaturesService.reset);

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Widget host({Brightness b = Brightness.light, double scale = 1.0, AppLanguage lang = AppLanguage.english}) {
    languageNotifier.value = lang;
    return LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(
        theme: AppTheme.build(b),
        builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
        home: TrackingV2Screen(bookingId: id),
      ),
    );
  }

  Booking fake(String status) => Booking.fromMap('b1', {'status': status});

  test('steps and progress: a trip moves along the line; a cancelled one has two steps and no progress', () {
    expect(trackingSteps(fake(BookingStatus.inTransit)), BookingStatus.flow);
    expect(trackingSteps(fake(BookingStatus.cancelled)), [BookingStatus.accepted, BookingStatus.cancelled]);
    expect(trackingProgress(fake(BookingStatus.cancelled)), isNull);
    expect(trackingProgress(fake(BookingStatus.accepted)), 0.05);
    expect(trackingProgress(fake(BookingStatus.delivered)), 1.0);
    final a = trackingProgress(fake(BookingStatus.pickedUp))!, b = trackingProgress(fake(BookingStatus.inTransit))!;
    expect(b, greaterThan(a));
  });

  testWidgets('shows route, status, codes, timeline, driver and the safety actions; no phone number', (t) async {
    t.view.physicalSize = const Size(360 * 2, 640 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(host());
    await settle(t);
    expect(find.byKey(const ValueKey('trkHeader')), findsOneWidget);
    expect(find.text('Accepted'), findsWidgets);
    await t.scrollUntilVisible(find.byKey(const ValueKey('trkTimeline')), 300, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const ValueKey('trkTimeline')), findsOneWidget);
    await t.scrollUntilVisible(find.byKey(const ValueKey('trkSos')), 300, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const ValueKey('trkSos')), findsOneWidget);
    expect(find.byKey(const ValueKey('trkCall')), findsOneWidget);
    expect(find.textContaining('+919800000000'), findsNothing);
  });

  testWidgets('dark, 2.0x text, Hindi and Urdu (RTL) lay out without overflow', (t) async {
    t.view.physicalSize = const Size(360 * 2, 640 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    for (final lang in [AppLanguage.hindi, AppLanguage.urdu]) {
      await t.pumpWidget(host(b: Brightness.dark, scale: 2.0, lang: lang));
      await settle(t);
      expect(t.takeException(), isNull, reason: lang.name);
    }
  });

  testWidgets('a delivered trip shows the rating, the papers and one-tap Book again (opens the booking steps)', (t) async {
    t.view.physicalSize = const Size(360 * 2, 640 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await db.collection('bookings').doc(id).update({'status': BookingStatus.delivered});
    await t.pumpWidget(host());
    await settle(t);
    await t.scrollUntilVisible(find.byKey(const ValueKey('bookAgain')), 300, scrollable: find.byType(Scrollable).first);
    await t.ensureVisible(find.byKey(const ValueKey('bookAgain')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('bookAgain')));
    await settle(t);
    expect(find.byType(BookWizardScreen), findsOneWidget);
  });

  testWidgets('the customer sees a clear Make bilty button (switch bilty on); it opens the bilty form; off hides it', (t) async {
    t.view.physicalSize = const Size(360 * 2, 640 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.bilty: true});
    await t.pumpWidget(host());
    await settle(t);
    await t.scrollUntilVisible(find.byKey(const ValueKey('biltyMake')), 300, scrollable: find.byType(Scrollable).first);
    await t.ensureVisible(find.byKey(const ValueKey('biltyMake')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('biltyMake')));
    await settle(t);
    expect(find.byType(LrFormScreen), findsOneWidget);

    FeaturesService.notifier.value = const Features(flags: {FeatureKey.bilty: false});
    await t.pumpWidget(host());
    await settle(t);
    expect(find.byKey(const ValueKey('biltyEntry'), skipOffstage: false), findsNothing);
  });

  testWidgets('openBookingTracking picks the new page with uiV2 on and the older one with it off', (t) async {
    late BuildContext ctx;
    Future<void> open(bool on) async {
      FeaturesService.notifier.value = Features(flags: {FeatureKey.uiV2: on});
      await t.pumpWidget(MaterialApp(key: UniqueKey(), home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })));
      openBookingTracking(ctx, id);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
    }

    await open(true);
    expect(find.byType(TrackingV2Screen), findsOneWidget);
    await open(false);
    expect(find.byType(BookingTrackingScreen), findsOneWidget);
    expect(find.byType(TrackingV2Screen), findsNothing);
  });
}
