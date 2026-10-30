// ignore_for_file: invalid_use_of_visible_for_testing_member
// E13: the design gallery. Draws the key screens in every look (Signature, Midnight, Classic), on a normal and a
// small phone, in several languages, to PNG with the real fonts, so a person can review spacing rhythm, alignment,
// cut text and contrast without a phone. Run it through tool/render_gallery.ps1 (it checks free memory first):
//   flutter test tool/render_gallery_test.dart                         -> build/gallery (the review set, about 50 images)
//   flutter test tool/render_gallery_test.dart --dart-define=FULL=true -> every screen x look x size x language
// Layout errors (overflow and the like) do not stop the run: each one is written to <OUT>/problems.txt, and the
// test fails at the end if there is any. It builds no app and opens no emulator; screens get fake data.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/admin/admin_dashboard_screen.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/dispatch/dispatch_models.dart';
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
import 'package:transport_app/core/settings/settings_screen.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/trust/public_trust.dart';
import 'package:transport_app/customer/customer_home_screen.dart';
import 'package:transport_app/customer/v2/tracking_v2_screen.dart';
import 'package:transport_app/driver/available_loads_view.dart';
import 'package:transport_app/driver/driver_trip_screen.dart';
import 'package:transport_app/driver/earnings_view.dart';

const _out = String.fromEnvironment('OUT', defaultValue: 'build/gallery');
const _full = bool.fromEnvironment('FULL');

/// The three looks of E7: Midnight is the Signature look at night.
enum Look {
  signature(ThemeStyle.signature, Brightness.light),
  midnight(ThemeStyle.signature, Brightness.dark),
  classic(ThemeStyle.classic, Brightness.light);

  final ThemeStyle style;
  final Brightness brightness;
  const Look(this.style, this.brightness);
}

/// A normal phone at 1.0x text and a small phone at 1.3x text (dp, saved at 2x).
enum Phone {
  m(Size(360, 640), 1.0),
  s(Size(320, 568), 1.3);

  final Size size;
  final double scale;
  const Phone(this.size, this.scale);
}

/// Every bundled font family (pubspec.yaml), so each language draws with its real glyphs.
Future<void> _loadFonts() async {
  final families = <String, List<String>>{
    'Mukta': ['assets/fonts/mukta/Mukta-Regular.ttf', 'assets/fonts/mukta/Mukta-Bold.ttf'],
    'NotoSans': ['assets/fonts/NotoSans-Regular.ttf'],
    'NotoSansKannada': ['assets/fonts/NotoSansKannada-Regular.ttf'],
    'NotoSansTamil': ['assets/fonts/NotoSansTamil-Regular.ttf'],
    'NotoSansTelugu': ['assets/fonts/NotoSansTelugu-Regular.ttf'],
    'NotoSansGujarati': ['assets/fonts/NotoSansGujarati-Regular.ttf'],
    'NotoSansBengali': ['assets/fonts/NotoSansBengali-Regular.ttf'],
    'NotoSansGurmukhi': ['assets/fonts/NotoSansGurmukhi-Regular.ttf'],
    'NotoNaskhArabic': ['assets/fonts/NotoNaskhArabic-Regular.ttf'],
  };
  for (final e in families.entries) {
    final loader = FontLoader(e.key);
    for (final path in e.value) {
      loader.addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
    }
    await loader.load();
  }
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(File('${Platform.environment['FLUTTER_ROOT'] ?? 'C:/src/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytesSync())));
  await icons.load();
}

/// The review set: every screen in every look (English, normal phone), every screen in Hindi, Tamil and Urdu
/// (Signature), and the small phone at 1.3x in Hindi Midnight and English Classic.
List<(Look, Phone, AppLanguage)> _matrix() {
  if (_full) {
    return [
      for (final l in Look.values)
        for (final p in Phone.values)
          for (final g in AppLanguage.values) (l, p, g),
    ];
  }
  return [
    for (final l in Look.values) (l, Phone.m, AppLanguage.english),
    for (final g in [AppLanguage.hindi, AppLanguage.tamil, AppLanguage.urdu]) (Look.signature, Phone.m, g),
    (Look.midnight, Phone.s, AppLanguage.hindi),
    (Look.classic, Phone.s, AppLanguage.english),
  ];
}

void main() {
  late FakeFirebaseFirestore db;
  String? uid;
  late String bookingId;
  late Load load;
  late Vehicle vehicle;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'customer1', phoneNumber: '+919800000001'));
    Backend.useFakes(db: db, uid: () => uid, auth: () => auth);
    TrustLookup.reader = (id) async => const PublicTrust(uid: 'x', trips: 80, rating: 4.7, ratingCount: 30, verified: true);
    uid = 'customer1';
    final loadId = await LoadService.post(pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: 25000, pickupDate: DateTime(2030, 10, 5), notes: '', mode: LoadMode.bid);
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

  testWidgets('draw the design gallery', (t) async {
    await t.runAsync(_loadFonts);
    Directory(_out).createSync(recursive: true);
    final problems = <String>[];
    var count = 0;
    final delivered = Booking(
      id: 'd1', loadId: 'L', driverId: 'driver1', vehicleId: 'v1', customerId: 'c1', status: BookingStatus.delivered, pickup: 'Pune', drop: 'Mumbai', cargoType: 'FMCG', weight: 2,
      vehicleType: '14ft', budget: 12000, pickupDate: null, notes: '', vehicleNumber: 'MH12AB1234', driverName: 'Ramesh Kumar', driverPhone: '', timeline: {BookingStatus.delivered: DateTime.now()}, paymentStatus: 'customer_marked_paid',
    );
    // name -> (who is signed in, the screen)
    final screens = <String, (String, Widget Function())>{
      'customer_home': ('customer1', () => const CustomerHomeScreen()),
      'tracking': ('customer1', () => TrackingV2Screen(bookingId: bookingId)),
      'driver_feed': ('driver1', () => Scaffold(body: AvailableLoadsView(loads: (_) => Stream.value(Paged.all([load])), origin: (lat: 28.6, lng: 77.2)))),
      'driver_trip': ('driver1', () => DriverTripScreen(bookingId: bookingId)),
      'earnings': ('driver1', () => Scaffold(body: EarningsView(bookings: () => Stream.value([delivered]), onOpenTrip: (_) {}))),
      'settings': ('customer1', () => SettingsScreen(onLogout: () async {})),
      'admin_home': ('driver1', () => const AdminDashboardScreen()),
    };

    for (final (look, phone, lang) in _matrix()) {
      for (final e in screens.entries) {
        final name = '${e.key}_${look.name}_${phone.name}_${lang.name}';
        uid = e.value.$1;
        final colors = look.style.colors(look.brightness);
        AppPalette.current = AppPalette.forColors(colors);
        AppPalette.currentColors = colors;
        t.view.physicalSize = phone.size * 2;
        t.view.devicePixelRatio = 2;
        await t.pumpWidget(const SizedBox()); // a fresh tree: no state carried over from the previous screen
        await t.pumpWidget(LanguageScope(
          notifier: ValueNotifier(lang),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            themeAnimationDuration: Duration.zero,
            theme: AppTheme.build(look.brightness, style: look.style),
            builder: (c, w) => MediaQuery(
              data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(phone.scale)),
              child: Directionality(textDirection: lang.textDirection, child: w!),
            ),
            home: RepaintBoundary(child: e.value.$2()),
          ),
        ));
        for (var i = 0; i < 8; i++) {
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
          await t.pump(const Duration(milliseconds: 100));
        }
        final err = t.takeException();
        if (err != null) problems.add('$name: ${err.toString().split('\n').first}');
        final boundary = find.byType(RepaintBoundary).evaluate().map((x) => x.renderObject).whereType<RenderRepaintBoundary>().first;
        await t.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
          File('$_out/$name.png').writeAsBytesSync(bytes.buffer.asUint8List());
          image.dispose();
        });
        count++;
      }
    }
    await t.pumpWidget(const SizedBox());
    t.view.reset();
    File('$_out/problems.txt').writeAsStringSync(problems.isEmpty ? 'none\n' : '${problems.join('\n')}\n');
    expect(count, _matrix().length * screens.length);
    expect(problems, isEmpty, reason: 'see $_out/problems.txt');
  });
}
