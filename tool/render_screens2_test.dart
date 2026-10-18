// Draws the Part 4 screens of U27 to U36 (driver, transporter, admin, customer home and tracking) to PNG with the real
// fonts, so a person can look for overlap, cut text and bad spacing (U42):
//   flutter test tool/render_screens2_test.dart            -> build/ux_png
// It builds no app and opens no emulator. Screens get fake data; nothing is sent anywhere.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/admin/admin_dashboard_screen.dart';
import 'package:transport_app/auth/driver_onboarding_card.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/dispatch/dispatch_models.dart';
import 'package:transport_app/core/dispatch/load_radar.dart';
import 'package:transport_app/core/dispatch/trust_lookup.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/paged.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/offer_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/transporter/transporter_logic.dart';
import 'package:transport_app/core/trust/public_trust.dart';
import 'package:transport_app/customer/customer_home_screen.dart';
import 'package:transport_app/customer/v2/tracking_v2_screen.dart';
import 'package:transport_app/driver/available_loads_view.dart';
import 'package:transport_app/driver/driver_trip_screen.dart';
import 'package:transport_app/driver/earnings_view.dart';
import 'package:transport_app/driver/my_offers_screen.dart';
import 'package:transport_app/driver/v2/driver_bid_sheet.dart';
import 'package:transport_app/driver/v2/incoming_load_screen.dart';
import 'package:transport_app/fleet/transporter_loads_screen.dart';

import 'render_kit_test.dart' as r;

void main() {
  late FakeFirebaseFirestore db;
  String? uid;
  late String loadId, bookingId;
  late Load load;
  late Vehicle vehicle;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'customer1', phoneNumber: '+919800000001'));
    Backend.useFakes(db: db, uid: () => uid, auth: () => auth);
    TrustLookup.reader = (id) async => const PublicTrust(uid: 'x', trips: 80, rating: 4.7, ratingCount: 30, verified: true);
    uid = 'customer1';
    loadId = await LoadService.post(pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: 25000, pickupDate: DateTime(2030, 10, 5), notes: '', mode: LoadMode.bid);
    load = Load.fromDoc(await db.collection('loads').doc(loadId).get());
    uid = 'driver1';
    await db.collection('users').doc('driver1').set({'driverName': 'Ramesh Kumar', 'phone': '+919800000000'});
    final vid = await VehicleService.add(number: 'MH12AB1234', type: '14ft', capacity: 4, rcNumber: 'RC');
    vehicle = Vehicle.fromDoc(await db.collection('vehicles').doc(vid).get());
    await OfferService.send(load: load, vehicle: vehicle, pricePaise: 2400000, etaMinutes: 30, pickupKm: 4);
    uid = 'customer1';
    final second = await LoadService.post(pickup: 'Pune', drop: 'Mumbai', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: 12000, pickupDate: DateTime(2030, 10, 6), notes: '');
    uid = 'driver1';
    bookingId = await BookingService.accept(loadId: second, vehicle: vehicle);
  });

  /// Like render_kit_test.renderPage, but waits for the fake database to answer before it takes the picture.
  Future<void> shot(WidgetTester t, String name, String who, Widget page, {double scale = 1.0, Brightness b = Brightness.light, AppLanguage lang = AppLanguage.english}) async {
    uid = who;
    AppPalette.current = b == Brightness.dark ? AppPalette.dark : AppPalette.light;
    t.view.physicalSize = const Size(720, 1280);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final dir = (lang == AppLanguage.urdu || lang == AppLanguage.kashmiri) ? TextDirection.rtl : TextDirection.ltr;
    final language = ValueNotifier(lang);
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(LanguageScope(
      notifier: language,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(b),
        builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: Directionality(textDirection: dir, child: w!)),
        home: RepaintBoundary(child: page),
      ),
    ));
    for (var i = 0; i < 8; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await t.pump(const Duration(milliseconds: 100));
    }
    final boundary = find.byType(RepaintBoundary).evaluate().map((e) => e.renderObject).whereType<RenderRepaintBoundary>().first;
    await t.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      const out = String.fromEnvironment('OUT', defaultValue: 'build/ux_png');
      Directory(out).createSync(recursive: true);
      File('$out/$name.png').writeAsBytesSync(bytes.buffer.asUint8List());
    });
  }

  testWidgets('draw the Part 4 screens of the driver, transporter, admin and customer', (t) async {
    await t.runAsync(r.loadFonts);
    final delivered = Booking(
      id: 'd1', loadId: 'L', driverId: 'driver1', vehicleId: 'v1', customerId: 'c1', status: BookingStatus.delivered, pickup: 'Pune', drop: 'Mumbai', cargoType: 'FMCG', weight: 2,
      vehicleType: '14ft', budget: 12000, pickupDate: null, notes: '', vehicleNumber: 'MH12AB1234', driverName: 'Ramesh Kumar', driverPhone: '', timeline: {BookingStatus.delivered: DateTime.now()}, paymentStatus: 'customer_marked_paid',
    );
    final radarLoads = StreamController<List<Load>>.broadcast();
    final radar = LoadRadar(loads: radarLoads.stream, vehicles: () async => [vehicle], origin: () => (lat: 28.6139, lng: 77.2090), driverId: () => 'driver1', wavesOn: () => false);
    radar.start();
    radarLoads.add([load]);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));

    await shot(t, 'p4_customer_home_en', 'customer1', const CustomerHomeScreen());
    await shot(t, 'p4_tracking_en', 'customer1', TrackingV2Screen(bookingId: bookingId));
    await shot(t, 'p4_incoming_en', 'driver1', IncomingLoadScreen(radar: radar, onAccepted: (_) {}, vehicles: () async => [vehicle]));
    await shot(t, 'p4_incoming_hi_dark', 'driver1', IncomingLoadScreen(radar: radar, onAccepted: (_) {}, vehicles: () async => [vehicle]), lang: AppLanguage.hindi, b: Brightness.dark);
    await shot(t, 'p4_bid_sheet_en', 'driver1', Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: DriverBidSheet(load: load, vehicle: vehicle, pickupKm: 4))));
    await shot(t, 'p4_feed_en', 'driver1', Scaffold(body: AvailableLoadsView(loads: (_) => Stream.value(Paged.all([load])), origin: (lat: 28.6, lng: 77.2))));
    await shot(t, 'p4_feed_ur_rtl', 'driver1', Scaffold(body: AvailableLoadsView(loads: (_) => Stream.value(Paged.all([load])), origin: (lat: 28.6, lng: 77.2))), lang: AppLanguage.urdu);
    await shot(t, 'p4_my_bids_en', 'driver1', MyOffersScreen(onOpenBooking: (_) {}));
    await shot(t, 'p4_trip_step_en', 'driver1', DriverTripScreen(bookingId: bookingId));
    await shot(t, 'p4_trip_step_hi_dark_1.3x', 'driver1', DriverTripScreen(bookingId: bookingId), lang: AppLanguage.hindi, b: Brightness.dark, scale: 1.3);
    await shot(t, 'p4_earnings_en', 'driver1', Scaffold(body: EarningsView(bookings: () => Stream.value([delivered]), onOpenTrip: (_) {})));
    await shot(t, 'p4_setup_rejected_en', 'driver1', Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: DriverOnboardingCard(user: const {'driverProfileComplete': true, 'verificationStatus': 'rejected', 'verificationMeta': {'reason': 'rc_mismatch', 'note': 'Plate differs'}}))));
    await shot(t, 'p4_transporter_loads_en', 'driver1', Scaffold(body: TransporterLoadsScreen(loads: Stream.value([load]), vehicles: () async => [vehicle], profile: () async => const TransporterProfile())));
    await shot(t, 'p4_admin_home_en', 'driver1', const AdminDashboardScreen());
    await t.runAsync(radar.dispose);
    await t.runAsync(radarLoads.close);
    expect(Directory('build/ux_png').listSync().where((f) => f.path.contains('p4_')).length, greaterThanOrEqualTo(14));
  });
}
