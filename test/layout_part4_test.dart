import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/admin/admin_dashboard_screen.dart';
import 'package:transport_app/auth/driver_onboarding_card.dart';
import 'package:transport_app/core/dispatch/dispatch_models.dart';
import 'package:transport_app/core/dispatch/trust_lookup.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/paged.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/booking_service.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/services/offer_service.dart';
import 'package:transport_app/core/services/vehicle_service.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/transporter/transporter_logic.dart';
import 'package:transport_app/customer/customer_home_screen.dart';
import 'package:transport_app/customer/v2/bid_room_screen.dart';
import 'package:transport_app/customer/v2/booking_wizard_model.dart';
import 'package:transport_app/customer/v2/booking_wizard_screen.dart';
import 'package:transport_app/customer/v2/tracking_v2_screen.dart';
import 'package:transport_app/driver/available_loads_view.dart';
import 'package:transport_app/driver/driver_trip_screen.dart';
import 'package:transport_app/driver/earnings_view.dart';
import 'package:transport_app/driver/my_offers_screen.dart';
import 'package:transport_app/driver/v2/driver_bid_sheet.dart';
import 'package:transport_app/fleet/transporter_loads_screen.dart';

/// U39: every new Part 4 screen at 360x640 in four ways: plain; dark with 2.0x text in Hindi; Urdu (right to left)
/// with 1.6x text; and Low-end mode. A screen passes when it lays out with no overflow and no other exception.
class _Variant {
  final String name;
  final Brightness brightness;
  final double scale;
  final AppLanguage lang;
  final bool lowEnd;
  const _Variant(this.name, this.brightness, this.scale, this.lang, this.lowEnd);
}

const _variants = [
  _Variant('plain', Brightness.light, 1.0, AppLanguage.english, false),
  _Variant('dark 2.0x Hindi', Brightness.dark, 2.0, AppLanguage.hindi, false),
  _Variant('Urdu RTL 1.6x', Brightness.light, 1.6, AppLanguage.urdu, false),
  _Variant('Low-end', Brightness.light, 1.0, AppLanguage.english, true),
];

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
    FeaturesService.reset();
    TrustLookup.reset();
    TrustLookup.reader = (id) async => null;
    LowEndMode.notifier.value = false;
    uid = 'customer1';
    loadId = await LoadService.post(pickup: 'Thiruvananthapuram', drop: 'Visakhapatnam', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: 25000, pickupDate: DateTime(2030, 10, 5), notes: '', mode: LoadMode.bid);
    load = Load.fromDoc(await db.collection('loads').doc(loadId).get());
    uid = 'driver1';
    await db.collection('users').doc('driver1').set({'driverName': 'Ramasubramanian', 'phone': '+919800000000'});
    final vid = await VehicleService.add(number: 'MH12AB1234', type: '14ft', capacity: 4, rcNumber: 'RC');
    vehicle = Vehicle.fromDoc(await db.collection('vehicles').doc(vid).get());
    await OfferService.send(load: load, vehicle: vehicle, pricePaise: 2500000, etaMinutes: 30, pickupKm: 4);
    uid = 'customer1';
    final second = await LoadService.post(pickup: 'Delhi', drop: 'Mumbai', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: 25000, pickupDate: DateTime(2030, 10, 6), notes: '');
    uid = 'driver1';
    bookingId = await BookingService.accept(loadId: second, vehicle: vehicle);
    uid = 'customer1';
  });
  tearDown(() {
    FeaturesService.reset();
    LowEndMode.notifier.value = false;
  });

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Booking delivered() => Booking(
        id: 'd1', loadId: 'L', driverId: 'driver1', vehicleId: 'v1', customerId: 'c1', status: BookingStatus.delivered, pickup: 'Thiruvananthapuram', drop: 'Visakhapatnam', cargoType: 'FMCG', weight: 2,
        vehicleType: '14ft', budget: 24000, pickupDate: null, notes: '', vehicleNumber: 'MH12AB1234', driverName: 'Ramasubramanian', driverPhone: '', timeline: {BookingStatus.delivered: DateTime.now()},
      );

  // Each entry says who is signed in and builds the screen.
  final screens = <String, (String, Widget Function())>{
    'customer home': ('customer1', () => const CustomerHomeScreen()),
    'book wizard': ('customer1', () => BookWizardScreen(initial: const WizardDraft(pickup: 'Delhi', drop: 'Jaipur', weightTons: 2, vehicleType: '14ft', step: 3))),
    'bid room': ('customer1', () => BidRoomScreen(loadId: loadId)),
    'tracking': ('customer1', () => TrackingV2Screen(bookingId: bookingId)),
    'driver trip': ('driver1', () => DriverTripScreen(bookingId: bookingId)),
    'loads feed': ('driver1', () => Scaffold(body: AvailableLoadsView(loads: (_) => Stream.value(Paged.all([load])), origin: (lat: 8.5, lng: 76.9)))),
    'my bids': ('driver1', () => MyOffersScreen(onOpenBooking: (_) {})),
    'bid sheet': ('driver1', () => Scaffold(body: SingleChildScrollView(child: DriverBidSheet(load: load, vehicle: vehicle, pickupKm: 4)))),
    'earnings': ('driver1', () => Scaffold(body: EarningsView(bookings: () => Stream.value([delivered()]), onOpenTrip: (_) {}))),
    'set-up card': ('driver1', () => Scaffold(body: SingleChildScrollView(child: DriverOnboardingCard(user: const {'driverProfileComplete': true, 'verificationStatus': 'rejected', 'verificationMeta': {'reason': 'rc_mismatch', 'note': 'Plate differs'}})))),
    'transporter loads': ('driver1', () => Scaffold(body: TransporterLoadsScreen(loads: Stream.value([load]), vehicles: () async => [vehicle], profile: () async => const TransporterProfile()))),
    'admin home': ('driver1', () => const AdminDashboardScreen()),
  };

  for (final entry in screens.entries) {
    for (final v in _variants) {
      testWidgets('${entry.key}: ${v.name}', (t) async {
        t.view.physicalSize = const Size(360 * 2, 640 * 2);
        t.view.devicePixelRatio = 2;
        addTearDown(t.view.reset);
        uid = entry.value.$1;
        languageNotifier.value = v.lang;
        LowEndMode.notifier.value = v.lowEnd;
        await t.pumpWidget(LanguageScope(
          notifier: languageNotifier,
          child: MaterialApp(
            theme: AppTheme.build(v.brightness),
            builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(v.scale)), child: w!),
            home: entry.value.$2(),
          ),
        ));
        await settle(t);
        expect(t.takeException(), isNull);
      });
    }
  }
}
