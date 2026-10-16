import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/documents/payment_card.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/khata/khata_models.dart';
import 'package:transport_app/core/khata/khata_screens.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/pricing/route_rates.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/share/business_card.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/trust/public_trust.dart';
import 'package:transport_app/core/trust/public_trust_card.dart';
import 'package:transport_app/driver/safety_checkin_card.dart';

/// G38 round 2: the screens added in Part 3 fit a 360 x 640 phone with 2.0x text in light and dark, in the longest
/// languages and in the two right-to-left ones, with the low-end switch on, and keep 48 dp targets, spoken labels
/// and readable contrast.
Booking _held() => Booking.fromMap('b1', {
      'customerId': 'customer1', 'driverId': 'driver1', 'status': 'in_transit', 'agreedFarePaise': 1234500000, 'paymentStatus': 'pending',
      'paymentHold': {'orderId': 'o1', 'paise': 1234500000}, 'pickup': 'Thiruvananthapuram', 'drop': 'Visakhapatnam', 'loadId': 'l', 'vehicleId': 'v',
      'cargoType': 'Fast moving consumer goods', 'weight': 12, 'vehicleType': '20ft', 'notes': '', 'vehicleNumber': 'TN01AB1234',
      'driverName': 'Ramasubramanian', 'driverPhone': '1', 'timeline': <String, Object?>{},
    });

const _profile = {
  'companyName': 'Sharma Roadlines Private Limited, Thiruvananthapuram',
  'phone': '+919876543210',
  'verified': true,
  'fleet': {'officeCity': 'Thiruvananthapuram', 'routes': ['Thiruvananthapuram - Visakhapatnam', 'Kochi - Mumbai'], 'vehicleTypes': ['20ft container', '32ft multi-axle'], 'vehicleCount': 120},
};

Widget _host(Widget w, Brightness b, AppLanguage lang, {double scale = 2.0}) {
  // The app builder sets the palette that the older widgets (AppCard, AppColors) read; the test does the same.
  AppPalette.current = b == Brightness.dark ? AppPalette.dark : AppPalette.light;
  return _hostBody(w, b, lang, scale);
}

Widget _hostBody(Widget w, Brightness b, AppLanguage lang, double scale) => LanguageScope(
      notifier: ValueNotifier(lang),
      child: MaterialApp(
        theme: AppTheme.build(b),
        home: MediaQuery(data: MediaQueryData(size: const Size(360, 640), textScaler: TextScaler.linear(scale)), child: Scaffold(body: SingleChildScrollView(child: w))),
      ),
    );

void main() {
  setUp(() {
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'customer1');
    FeaturesService.notifier.value = const Features(flags: {
      FeatureKey.tripTrustCard: true, FeatureKey.rateRange: true, FeatureKey.safetyCheckin: true, FeatureKey.khata: true, FeatureKey.bizCard: true, FeatureKey.paymentGateway: true,
    });
  });
  tearDown(() {
    FeaturesService.reset();
    LowEndMode.notifier.value = false;
    AppPalette.current = AppPalette.light;
  });

  final widgets = <String, Widget Function()>{
    'trust card': () => PublicTrustCard(driverId: 'd1', source: Stream.value(const PublicTrust(uid: 'd1', trips: 12345, rating: 4.8, ratingCount: 9999, verified: true, since: '2024-11'))),
    'rate range': () => RateRangeLine(pickup: 'Mumbai', drop: 'Jaipur', vehicleType: '14ft', source: Future.value(const RateRange(1200000000, 1300000000, 1400000000, 30))),
    'check-in': () => const SafetyCheckinCard(),
    'held payment': () => PaymentCard(booking: _held()),
    'khata list': () => SizedBox(height: 600, child: KhataScreen(source: Stream.value(const [KhataParty(id: 'a', name: 'Sharma Roadlines Private Limited', note: 'Thiruvananthapuram depot', balancePaise: 123456789012)]))),
    'khata party': () => SizedBox(height: 600, child: KhataPartyScreen(party: const KhataParty(id: 'a', name: 'Sharma Roadlines'), source: Stream.value([KhataEntry(id: '1', kind: 'owed', amountPaise: 123456789, note: 'Thiruvananthapuram to Visakhapatnam', date: DateTime(2026, 10, 1))]))),
    'business card': () => SizedBox(height: 900, child: const BusinessCardScreen(profile: _profile)),
  };

  const languages = [AppLanguage.english, AppLanguage.hindi, AppLanguage.tamil, AppLanguage.telugu, AppLanguage.kannada, AppLanguage.urdu, AppLanguage.kashmiri];

  for (final entry in widgets.entries) {
    for (final lang in languages) {
      for (final b in Brightness.values) {
        testWidgets('${entry.key}: ${lang.name} ${b.name} at 2.0x text', (t) async {
          t.view.physicalSize = const Size(360, 640);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          await t.pumpWidget(_host(entry.value(), b, lang));
          await t.pump(const Duration(milliseconds: 50));
          expect(t.takeException(), isNull, reason: 'overflow or error in ${entry.key}');
        });
      }
    }
  }

  testWidgets('low-end mode: the same screens draw without error', (t) async {
    LowEndMode.notifier.value = true;
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    for (final w in widgets.values) {
      await t.pumpWidget(_host(w(), Brightness.light, AppLanguage.hindi));
      await t.pump(const Duration(milliseconds: 50));
      expect(t.takeException(), isNull);
    }
  });

  for (final b in Brightness.values) {
    for (final name in ['trust card', 'check-in', 'held payment', 'khata party']) {
      testWidgets('$name: tap targets, labels and contrast (${b.name})', (t) async {
        final h = t.ensureSemantics();
        t.view.physicalSize = const Size(360, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(_host(widgets[name]!(), b, AppLanguage.english, scale: 1.0));
        await t.pump(const Duration(milliseconds: 50));
        await expectLater(t, meetsGuideline(androidTapTargetGuideline));
        await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(t, meetsGuideline(textContrastGuideline));
        h.dispose();
      });
    }
  }
}
