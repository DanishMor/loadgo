import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/dispatch/dispatch_models.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/pricing/route_rates.dart';
import 'package:transport_app/core/scheduling/schedule.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/services/pricing_service.dart';
import 'package:transport_app/core/services/vehicle_type_service.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/widgets/ds/fare_meter.dart';
import 'package:transport_app/core/widgets/ds/slide_to_confirm.dart';
import 'package:transport_app/customer/v2/booking_wizard_model.dart';
import 'package:transport_app/customer/v2/booking_wizard_screen.dart';

/// U19: the five-step booking.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'customer1');
    PricingService.reset();
    VehicleTypeService.reset();
    FeaturesService.reset();
    languageNotifier.value = AppLanguage.english;
  });

  const full = WizardDraft(pickup: 'Delhi', drop: 'Jaipur', cargo: 'FMCG', weightTons: 3, vehicleType: '14ft');

  group('WizardDraft', () {
    test('each step says what is missing, in a key, and nothing when it is complete', () {
      const d = WizardDraft();
      expect(d.stepError(0), 'wzNeedRoute');
      expect(d.copyWith(pickup: 'Delhi').stepError(0), 'wzNeedRoute');
      expect(d.copyWith(pickup: 'Delhi', drop: 'Jaipur').stepError(0), isNull);
      expect(d.stepError(1), 'wzNeedGoods');
      expect(d.copyWith(weightTons: () => 0.4).stepError(1), 'wzNeedGoods');
      expect(d.copyWith(weightTons: () => 41).stepError(1), 'wzNeedGoods');
      expect(d.copyWith(weightTons: () => 3).stepError(1), isNull);
      expect(d.stepError(2), 'wzNeedTruck');
      expect(full.stepError(2), isNull);
      expect(full.stepError(4), isNull);
    });

    test('the price step needs a price: the estimate is the default, an unknown route needs a typed price', () {
      expect(full.estimatePaise, isNotNull);
      expect(full.effectivePricePaise, WizardDraft.roundTo10Rupees(full.estimatePaise));
      expect(full.stepError(3), isNull);
      const noRoute = WizardDraft(pickup: 'Nowhereville', drop: 'Elsewhere', vehicleType: '14ft', weightTons: 3);
      expect(noRoute.estimatePaise, isNull);
      expect(noRoute.stepError(3), 'wzNeedPrice');
      expect(noRoute.copyWith(pricePaise: () => 500000).stepError(3), isNull);
      expect(full.copyWith(pricePaise: () => 100000001).stepError(3), 'wzNeedPrice');
    });

    test('a scheduled booking needs a time inside the allowed window', () {
      final now = DateTime(2030, 1, 1, 12);
      const rules = ScheduleRules(minMinutes: 30, leadMinutes: 120, maxDays: 30, freeCancelHours: 2);
      final s = full.copyWith(mode: LoadMode.scheduled);
      expect(s.stepError(3, now: now, rules: rules), 'wzNeedDate');
      expect(s.copyWith(scheduledAt: () => now.add(const Duration(minutes: 10))).stepError(3, now: now, rules: rules), 'wzDateTooSoon');
      expect(s.copyWith(scheduledAt: () => now.add(const Duration(days: 40))).stepError(3, now: now, rules: rules), 'wzDateTooFar');
      expect(s.copyWith(scheduledAt: () => now.add(const Duration(hours: 5))).stepError(3, now: now, rules: rules), isNull);
    });

    test('firstIncomplete finds the first step to fix', () {
      expect(const WizardDraft().firstIncomplete(), 0);
      expect(const WizardDraft(pickup: 'Delhi', drop: 'Jaipur').firstIncomplete(), 1);
      expect(const WizardDraft(pickup: 'Delhi', drop: 'Jaipur', weightTons: 2).firstIncomplete(), 2);
      expect(full.firstIncomplete(), isNull);
    });

    test('the price is whole rupees in paise and the budget is the rounded rupees', () {
      expect(WizardDraft.roundTo10Rupees(123456), 123000);
      expect(WizardDraft.roundTo10Rupees(123500), 124000);
      expect(WizardDraft.roundTo10Rupees(null), isNull);
      expect(full.copyWith(pricePaise: () => 2345000).budgetRupees, 23450);
    });

    test('json round trip keeps good values; damaged ones are dropped, never thrown', () {
      final back = WizardDraft.fromJson(full.copyWith(mode: LoadMode.bid, pricePaise: () => 4000000, step: 3).toJson());
      expect((back.pickup, back.cargo, back.weightTons, back.vehicleType, back.mode, back.pricePaise, back.step), ('Delhi', 'FMCG', 3.0, '14ft', LoadMode.bid, 4000000, 3));
      final bad = WizardDraft.fromJson({'pickup': 5, 'cargo': 'Nuclear', 'weight': 'heavy', 'vehicle': '', 'mode': 'auction', 'price': -4, 'at': 'soon', 'step': 99});
      expect((bad.pickup, bad.cargo, bad.weightTons, bad.vehicleType, bad.mode, bad.pricePaise, bad.scheduledAt, bad.step), ('', 'General', null, null, LoadMode.instant, null, null, 4));
      expect(WizardDraft.fromJson('nonsense').pickup, '');
      expect(WizardDraft.fromJson(null).step, 0);
    });
  });

  group('WizardDraftStore', () {
    test('saves, loads and forgets after 7 days; an empty draft is not kept', () async {
      final now = DateTime(2030, 1, 1);
      await WizardDraftStore.save(full, now: now);
      expect((await WizardDraftStore.load(now: now.add(const Duration(days: 6))))!.pickup, 'Delhi');
      expect(await WizardDraftStore.load(now: now.add(const Duration(days: 8))), isNull);
      expect(await WizardDraftStore.load(now: now), isNull, reason: 'removed once it was too old');
      await WizardDraftStore.save(full, now: now);
      await WizardDraftStore.save(const WizardDraft(), now: now);
      expect(await WizardDraftStore.load(now: now), isNull);
      SharedPreferences.setMockInitialValues({'wizard_draft_customer1': 'not json'});
      expect(await WizardDraftStore.load(), isNull);
    });
  });

  Widget host(Widget home, {double scale = 1.0, Brightness b = Brightness.light, AppLanguage lang = AppLanguage.english, bool lowEnd = false}) {
    languageNotifier.value = lang;
    return LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(
        theme: AppTheme.build(b, lowEnd: lowEnd),
        builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
        home: home,
      ),
    );
  }

  Future<void> open(WidgetTester t, Widget wizard) async {
    await t.pumpWidget(host(Builder(builder: (c) => Scaffold(body: Center(child: ElevatedButton(onPressed: () => Navigator.of(c).push(MaterialPageRoute<String>(builder: (_) => wizard)), child: const Text('open')))))));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  Finder field(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextField));

  testWidgets('the whole booking: route, goods, truck, price and mode, slide: posts once and gives back the load id', (t) async {
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final posted = <WizardDraft>[];
    String? result;
    await t.pumpWidget(host(Builder(builder: (c) => Scaffold(body: Center(child: ElevatedButton(onPressed: () async => result = await Navigator.of(c).push<String>(MaterialPageRoute(builder: (_) => BookWizardScreen(poster: (d) async {
      posted.add(d);
      return 'load42';
    }, bidAvailable: true))), child: const Text('open')))))));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    // 1 route: Next with nothing says what is missing and stays
    expect(find.text('Where should the truck go?'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('wzNext')));
    await t.pumpAndSettle();
    expect(find.text('Choose both cities.'), findsOneWidget);
    await t.enterText(field('wzPickupField'), 'Delhi');
    await t.enterText(field('wzDropField'), 'Jaipur');
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('wzRibbon')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('wzNext')));
    await t.pumpAndSettle();

    // 2 goods
    expect(find.text('What are you sending?'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('wzNext')));
    await t.pumpAndSettle();
    expect(find.text('Choose what you send and the weight.'), findsOneWidget);
    await t.drag(find.byKey(const ValueKey('wzWeightSlider')), const Offset(120, 0));
    await t.pumpAndSettle();
    await t.tap(find.text('FMCG'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('wzNext')));
    await t.pumpAndSettle();

    // 3 truck: nothing chosen yet
    expect(find.text('Which truck?'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('wzNext')));
    await t.pumpAndSettle();
    expect(find.text('Choose a truck.'), findsOneWidget);
    expect(find.text('Fits your load'), findsOneWidget, reason: 'the suggested truck is marked');
    await t.tap(find.ancestor(of: find.text('Fits your load'), matching: find.byType(InkWell)).first);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('wzNext')));
    await t.pumpAndSettle();

    // 4 price and mode
    expect(find.byType(FareMeter), findsOneWidget);
    expect(find.byKey(const ValueKey('wzMode_bid')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('wzMode_bid')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('wzNext')));
    await t.pumpAndSettle();

    // 5 review and slide
    expect(find.text('Check and book'), findsOneWidget);
    expect(find.byKey(const ValueKey('wzReviewPrice')), findsOneWidget);
    expect(find.textContaining('terms of'), findsOneWidget);
    await t.drag(find.byKey(const ValueKey('slideThumb')), const Offset(1200, 0));
    await t.pumpAndSettle();
    expect(posted, hasLength(1));
    expect((posted.single.pickup, posted.single.drop, posted.single.cargo, posted.single.mode), ('Delhi', 'Jaipur', 'FMCG', LoadMode.bid));
    expect(posted.single.vehicleType, isNotNull);
    expect(posted.single.weightTons, greaterThan(2));
    expect(result, 'load42');
    expect(await WizardDraftStore.load(), isNull, reason: 'a posted booking leaves no draft behind');
  });

  testWidgets('bid mode is not offered while dispatchV2 is off', (t) async {
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(host(BookWizardScreen(initial: full.copyWith(step: 3))));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('wzMode_instant')), findsOneWidget);
    expect(find.byKey(const ValueKey('wzMode_bid')), findsNothing);
    expect(find.byKey(const ValueKey('wzMode_scheduled')), findsOneWidget);
  });

  testWidgets('Back keeps every answer; the system back button goes a step back, then leaves', (t) async {
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await open(t, BookWizardScreen(initial: full.copyWith(step: 2)));
    await t.tap(find.byKey(const ValueKey('wzTruck_14ft')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('wzBack')));
    await t.pumpAndSettle();
    expect(find.text('What are you sending?'), findsOneWidget);
    expect(find.text('Weight: 3 tons'), findsOneWidget, reason: 'the weight is still there');
    await t.tap(find.byKey(const ValueKey('wzNext')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('wzTruck_14ft')), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('What are you sending?'), findsOneWidget, reason: 'system back = previous step');
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('Where should the truck go?'), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('Where should the truck go?'), findsNothing, reason: 'the first step lets the person leave');
  });

  testWidgets('a saved draft comes back with a note, and a failed post keeps the booking and the slide resets', (t) async {
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await WizardDraftStore.save(full.copyWith(step: 4));
    var calls = 0;
    await open(t, BookWizardScreen(poster: (d) async {
      calls++;
      throw StateError('network');
    }));
    await t.pumpAndSettle();
    expect(find.text('Check and book'), findsOneWidget, reason: 'the draft was on the last step');
    await t.drag(find.byKey(const ValueKey('slideThumb')), const Offset(1200, 0));
    await t.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Check and book'), findsOneWidget, reason: 'still here');
    expect(t.widget<SlideToConfirm>(find.byType(SlideToConfirm)).enabled, isTrue);
    expect(await WizardDraftStore.load(), isNotNull, reason: 'the draft is kept');
  });

  testWidgets('a weight that no longer fits the chosen truck drops the truck choice', (t) async {
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(host(BookWizardScreen(initial: const WizardDraft(pickup: 'Delhi', drop: 'Jaipur', weightTons: 1, vehicleType: 'Bike', step: 1))));
    await t.pumpAndSettle();
    await t.drag(find.byKey(const ValueKey('wzWeightSlider')), const Offset(600, 0));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('wzNext')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('wzNext')));
    await t.pumpAndSettle();
    expect(find.text('Choose a truck.'), findsOneWidget);
  });

  testWidgets('the usual price of the route reaches the fare meter', (t) async {
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(host(BookWizardScreen(initial: full.copyWith(step: 3), rateSource: (a, b, v) async => const RateRange(2000000, 2500000, 3000000, 12))));
    await t.pumpAndSettle();
    expect(find.textContaining('Usual price'), findsOneWidget);
  });

  testWidgets('an unknown route asks for a typed price', (t) async {
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(host(BookWizardScreen(initial: const WizardDraft(pickup: 'Nowhereville', drop: 'Elsewhere', weightTons: 2, vehicleType: '14ft', step: 3))));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('wzOwnPrice')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('wzNext')));
    await t.pumpAndSettle();
    expect(find.text('Type your price.'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('wzOwnPrice')), '18000');
    await t.tap(find.byKey(const ValueKey('wzNext')));
    await t.pumpAndSettle();
    expect(find.text('Check and book'), findsOneWidget);
  });

  for (final lang in [AppLanguage.english, AppLanguage.hindi, AppLanguage.urdu]) {
    for (final b in Brightness.values) {
      for (var step = 0; step < 5; step++) {
        testWidgets('step ${step + 1} fits 360x640 at 2.0x text: ${lang.name} ${b.name}', (t) async {
          t.view.physicalSize = const Size(360, 640);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          await t.pumpWidget(host(BookWizardScreen(initial: full.copyWith(step: step), bidAvailable: true), scale: 2.0, b: b, lang: lang));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          expect(find.byType(Scrollable), findsWidgets);
        });
      }
    }
  }

  group('E28 round trip', () {
    test('the way back swaps the places, is scheduled and keeps goods, truck and price', () {
      final at = DateTime(2030, 1, 2, 9);
      final back = full.copyWith(pricePaise: () => 2500000).returnTrip(at);
      expect((back.pickup, back.drop, back.mode, back.scheduledAt, back.vehicleType, back.pricePaise), ('Jaipur', 'Delhi', LoadMode.scheduled, at, '14ft', 2500000));
      final now = DateTime(2030, 1, 1, 10);
      expect(WizardDraft.defaultReturn(null, now), DateTime(2030, 1, 2, 10));
      expect(WizardDraft.returnOk(DateTime(2030, 1, 1, 9), null, now), isFalse);
      expect(WizardDraft.returnOk(DateTime(2030, 1, 3), DateTime(2030, 1, 4), now), isFalse, reason: 'before the outbound pickup');
      expect(WizardDraft.returnOk(DateTime(2030, 1, 5), DateTime(2030, 1, 4), now), isTrue);
    });

    testWidgets('with roundTrip on: the switch posts the outbound load, then the way back; off: one post', (t) async {
      t.view.physicalSize = const Size(800, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final posted = <WizardDraft>[];
      Future<String> poster(WizardDraft d) async {
        posted.add(d);
        return 'L${posted.length}';
      }

      await open(t, BookWizardScreen(initial: full.copyWith(step: 4), poster: poster));
      expect(find.byKey(const ValueKey('wzReturn')), findsNothing);
      await t.drag(find.byKey(const ValueKey('slideThumb')), const Offset(1200, 0));
      await t.pumpAndSettle();
      expect(posted.length, 1);

      posted.clear();
      FeaturesService.notifier.value = const Features(flags: {FeatureKey.roundTrip: true});
      await open(t, BookWizardScreen(initial: full.copyWith(step: 4), poster: poster));
      await t.tap(find.byKey(const ValueKey('wzReturn')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('wzReturnWhen')), findsOneWidget);
      await t.drag(find.byKey(const ValueKey('slideThumb')), const Offset(1200, 0));
      await t.pumpAndSettle();
      expect(posted.map((d) => '${d.pickup}>${d.drop}'), ['Delhi>Jaipur', 'Jaipur>Delhi']);
      expect(posted.last.mode, LoadMode.scheduled);
    });

    testWidgets('a failed way back keeps the outbound load and says so', (t) async {
      t.view.physicalSize = const Size(800, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      FeaturesService.notifier.value = const Features(flags: {FeatureKey.roundTrip: true});
      var calls = 0;
      await open(t, BookWizardScreen(initial: full.copyWith(step: 4), poster: (d) async {
        calls++;
        if (calls == 2) throw StateError('network');
        return 'L1';
      }));
      await t.tap(find.byKey(const ValueKey('wzReturn')));
      await t.pumpAndSettle();
      await t.drag(find.byKey(const ValueKey('slideThumb')), const Offset(1200, 0));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(calls, 2);
      expect(find.text(T.get('wzReturnFailed', AppLanguage.english)), findsOneWidget);
    });
  });

  testWidgets('E27: See the full price only with priceCard on; it opens every line and the promise', (t) async {
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await open(t, BookWizardScreen(initial: full.copyWith(step: 3)));
    expect(find.byKey(const ValueKey('wzSeeFullPrice')), findsNothing);
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.priceCard: true});
    await t.pumpWidget(const SizedBox());
    await open(t, BookWizardScreen(initial: full.copyWith(step: 3)));
    await t.tap(find.byKey(const ValueKey('wzSeeFullPrice')).last);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('ptPromise')), findsOneWidget);
  });

  testWidgets('E31: Share this quote only with quoteShare on; it opens the quote card', (t) async {
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await open(t, BookWizardScreen(initial: full.copyWith(step: 4)));
    expect(find.byKey(const ValueKey('wzShareQuote')), findsNothing);
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.quoteShare: true});
    await t.pumpWidget(const SizedBox());
    await open(t, BookWizardScreen(initial: full.copyWith(step: 4)));
    await t.tap(find.byKey(const ValueKey('wzShareQuote')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('qsCard')), findsOneWidget);
    expect(find.text('Delhi'), findsWidgets);
  });
}
