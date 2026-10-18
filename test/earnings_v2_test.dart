import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/driver/earnings_view.dart';
import 'package:transport_app/driver/v2/earnings_v2.dart';

import 'test_utils.dart';

/// U33: earnings with the day first and where the rest of the money is.
final now = DateTime(2026, 10, 8, 15);

void main() {
  late FakeFirebaseFirestore db;
  setUp(() {
    FeaturesService.reset();
    db = FakeFirebaseFirestore();
    languageNotifier.value = AppLanguage.english;
  });
  tearDown(FeaturesService.reset);

  Future<Booking> mk(String id, {required String pay, num budget = 1000, DateTime? at}) async {
    await db.collection('bookings').doc(id).set({
      'driverId': 'driver1',
      'customerId': 'customer1',
      'status': 'delivered',
      'pickup': 'P$id',
      'drop': 'D$id',
      'budget': budget,
      'paymentStatus': pay,
      'timeline': {'delivered': Timestamp.fromDate(at ?? DateTime(2026, 10, 8, 9))},
    });
    return Booking.fromDoc(await db.collection('bookings').doc(id).get());
  }

  test('moneyStageOf and moneyByStage: pending waits for the customer, marked paid waits for the driver, confirmed is in the wallet', () async {
    final a = await mk('a', pay: 'pending', budget: 1000);
    final b = await mk('b', pay: 'customer_marked_paid', budget: 2000);
    final c = await mk('c', pay: 'driver_confirmed', budget: 3000);
    expect(moneyStageOf(a), MoneyStage.waitCustomer);
    expect(moneyStageOf(b), MoneyStage.confirmReceived);
    expect(moneyStageOf(c), MoneyStage.inWallet);
    final m = moneyByStage([a, b, c]);
    expect(m[MoneyStage.waitCustomer], 100000);
    expect(m[MoneyStage.confirmReceived], 200000);
    expect(m[MoneyStage.inWallet], 300000);
    expect(moneyByStage(const []).values.every((v) => v == 0), isTrue);
  });

  Future<void> show(WidgetTester t, List<Booking> list, {Brightness b = Brightness.light, double scale = 1}) async {
    t.view.physicalSize = const Size(360 * 2, 900 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(
        theme: AppTheme.build(b),
        builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
        home: Scaffold(body: EarningsView(bookings: () => Stream.value(list), onOpenTrip: (_) {}, now: () => now)),
      ),
    ));
    await settle(t);
  }

  testWidgets('the money section shows each stage with its amount', (t) async {
    late List<Booking> list;
    await t.runAsync(() async => list = [await mk('a', pay: 'pending', budget: 1000), await mk('b', pay: 'driver_confirmed', budget: 3000)]);
    await show(t, list);
    expect(find.byKey(const ValueKey('epHero')), findsOneWidget);
    await t.scrollUntilVisible(find.byKey(const ValueKey('epMoney')), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Where your money is'), findsOneWidget);
    expect(find.text('Waiting for the customer to pay'), findsWidgets);
    expect(find.byKey(const ValueKey('epStage_waitCustomer')), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const ValueKey('epStage_inWallet'))).data, '₹ 3,000');
  });

  testWidgets('empty: no money section, the empty text', (t) async {
    await show(t, const []);
    expect(find.byKey(const ValueKey('epMoney')), findsNothing);
    await t.scrollUntilVisible(find.text('No completed trips yet'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('No completed trips yet'), findsOneWidget);
  });

  testWidgets('dark, 2.0x text and Hindi: no overflow', (t) async {
    late List<Booking> list;
    await t.runAsync(() async => list = [await mk('a', pay: 'customer_marked_paid')]);
    languageNotifier.value = AppLanguage.hindi;
    await show(t, list, b: Brightness.dark, scale: 2);
    expect(t.takeException(), isNull);
  });

  testWidgets('uiV2 off: the old tab, without the money section', (t) async {
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.uiV2: false});
    late List<Booking> list;
    await t.runAsync(() async => list = [await mk('a', pay: 'pending')]);
    await show(t, list);
    expect(find.byKey(const ValueKey('epHero')), findsNothing);
  });
}
