import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/admin/admin_city_notes_screen.dart';
import 'package:transport_app/core/adapters/adapters.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/pricing/city_notes.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/services/pricing_service.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/vehicles/vehicle_catalog.dart';
import 'package:transport_app/core/widgets/price_transparency_sheet.dart';
import 'package:transport_app/customer/v2/booking_wizard_model.dart';
import 'package:transport_app/customer/v2/booking_wizard_screen.dart';

/// E33: expected tolls (flag tollEstimate) and admin city notes (flag cityNotes).
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'c1');
    FeaturesService.reset();
    CityNotesService.reset();
    languageNotifier.value = AppLanguage.english;
  });
  tearDown(FeaturesService.reset);

  CostGuard guard() => CostGuard(const CostCaps(daily: 1000, perUser: 30), killed: () => false);

  test('city notes: defensive parse, aliases match, trimmed and capped', () {
    final n = CityNotes.fromMap({
      'notes': {'Mumbai': '  Trucks may enter only after 10 pm.  ', 'X': 'too short a key', 'Pune': 7, 'Delhi': 'n' * 400},
    });
    expect(n.notes.keys.toSet(), {'Mumbai', 'Delhi'});
    expect(n.noteFor('mumbai'), 'Trucks may enter only after 10 pm.');
    expect(n.noteFor('Bombay'), isNotNull, reason: 'alias through the city table');
    expect(n.noteFor('Delhi')!.length, CityNotes.maxChars);
    expect(n.noteFor('Surat'), isNull);
    expect(CityNotes.fromMap(null).notes, isEmpty);
    expect(CityNotes.fromMap({'notes': 'x'}).notes, isEmpty);
  });

  test('city notes: saved to config/city_notes and read back once per session', () async {
    await CityNotesService.save(const CityNotes({'Surat': 'Market closed on Sunday.'}));
    CityNotesService.reset();
    expect((await CityNotesService.load()).noteFor('Surat'), 'Market closed on Sunday.');
  });

  testWidgets('tolls: none by default; the fake gives a value with the axles of the vehicle; same city or unknown gives none', (t) async {
    final specs = (await t.runAsync(() => VehicleCatalog.load()))!;
    expect(await t.runAsync(() => TollLine.estimate('Pune', 'Mumbai', '14ft', guardOverride: guard(), catalog: () async => specs)), isNull);
    final two = await t.runAsync(() => TollLine.estimate('Pune', 'Mumbai', '14ft', via: const FakeTollEstimator(), guardOverride: guard(), catalog: () async => specs));
    expect(two, greaterThan(0));
    expect(await t.runAsync(() => TollLine.estimate('Pune', 'Pune', '14ft', via: const FakeTollEstimator(), guardOverride: guard())), isNull);
    expect(await t.runAsync(() => TollLine.estimate('Nowhere', 'Mumbai', '14ft', via: const FakeTollEstimator(), guardOverride: guard())), isNull);
  });

  Widget host(Widget child, {AppLanguage lang = AppLanguage.english, Brightness b = Brightness.light, double scale = 1}) => LanguageScope(
        notifier: ValueNotifier(lang),
        child: MaterialApp(
          theme: AppTheme.build(b, style: ThemeStyle.signature),
          builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: Directionality(textDirection: lang.textDirection, child: w!)),
          home: child,
        ),
      );

  testWidgets('price card: the toll line is apart from the price and only when known', (t) async {
    final f = PricingService.quote(vehicleType: '14ft', distanceKm: 150);
    await t.pumpWidget(host(Scaffold(body: SingleChildScrollView(child: PriceTransparencySheet(fare: f, tollPaise: 85000)))));
    expect(find.byKey(const ValueKey('pxToll')), findsOneWidget);
    await t.pumpWidget(host(Scaffold(body: SingleChildScrollView(child: PriceTransparencySheet(fare: f)))));
    expect(find.byKey(const ValueKey('pxToll')), findsNothing);
  });

  testWidgets('wizard route step: notes for the pickup and drop city only with cityNotes on', (t) async {
    t.view.physicalSize = const Size(800, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    const notes = CityNotes({'Mumbai': 'Trucks may enter only after 10 pm.'});
    const draft = WizardDraft(pickup: 'Pune', drop: 'Mumbai', cargo: 'FMCG', weightTons: 3, vehicleType: '14ft');
    await t.pumpWidget(host(BookWizardScreen(initial: draft, cityNotes: () async => notes)));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('wzCityNote_drop')), findsNothing);
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.cityNotes: true});
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(host(BookWizardScreen(initial: draft, cityNotes: () async => notes)));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('wzCityNote_drop')), findsOneWidget);
    expect(find.byKey(const ValueKey('wzCityNote_pickup')), findsNothing);
    expect(find.text('Trucks may enter only after 10 pm.'), findsOneWidget);
  });

  testWidgets('admin: add, edit and remove notes; each change is saved', (t) async {
    final saved = <CityNotes>[];
    await t.pumpWidget(host(AdminCityNotesScreen(load: () async => CityNotes.empty, save: (n) async => saved.add(n))));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('cnNone')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('cnAdd')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('cnCity')), 'Surat');
    await t.enterText(find.byKey(const ValueKey('cnNote')), 'Market closed on Sunday.');
    await t.tap(find.byKey(const ValueKey('cnSave')));
    await t.pumpAndSettle();
    expect(saved.last.notes, {'Surat': 'Market closed on Sunday.'});
    await t.tap(find.byKey(const ValueKey('cnDelete_Surat')));
    await t.pumpAndSettle();
    expect(saved.last.notes, isEmpty);
  });

  for (final (lang, b) in [(AppLanguage.hindi, Brightness.light), (AppLanguage.urdu, Brightness.dark), (AppLanguage.tamil, Brightness.dark)]) {
    testWidgets('no overflow at 320 dp and 2.0x: ${lang.name} ${b.name}', (t) async {
      t.view.physicalSize = const Size(320, 1800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(host(AdminCityNotesScreen(load: () async => const CityNotes({'Mumbai': 'Trucks may enter only after 10 pm on weekdays.'})), lang: lang, b: b, scale: 2));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
}
