import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/services/pricing_service.dart';
import 'package:transport_app/core/services/vehicle_type_service.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/vehicles/vehicle_catalog.dart';
import 'package:transport_app/core/vehicles/vehicle_painter.dart';
import 'package:transport_app/core/vehicles/vehicle_screens.dart';
import 'package:transport_app/core/widgets/ds/bid_card.dart';
import 'package:transport_app/customer/v2/booking_wizard_model.dart';
import 'package:transport_app/customer/v2/booking_wizard_screen.dart';

/// E17b: the vehicleCatalog flag. OFF: the booking truck step is exactly as before. ON: drawings on each truck
/// and "See all vehicles", whose choice comes back into the booking.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'customer1');
    PricingService.reset();
    VehicleTypeService.reset();
    FeaturesService.reset();
    languageNotifier.value = AppLanguage.english;
  });
  tearDown(FeaturesService.reset);

  const draft = WizardDraft(pickup: 'Delhi', drop: 'Jaipur', cargo: 'FMCG', weightTons: 3, step: 2);

  Future<void> openWizard(WidgetTester t) async {
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.runAsync(() => VehicleCatalog.load());
    await t.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: Builder(builder: (c) => Scaffold(body: Center(child: ElevatedButton(onPressed: () => Navigator.of(c).push(MaterialPageRoute<String>(builder: (_) => const BookWizardScreen(initial: draft))), child: const Text('open'))))),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  test('the flag is registered OFF in pilot and normal mode', () {
    final spec = Features.registry.firstWhere((s) => s.key == FeatureKey.vehicleCatalog);
    expect(spec.pilotOn, isFalse);
    expect(spec.normalOn, isFalse);
    expect(FeaturesService.isOn(FeatureKey.vehicleCatalog), isFalse);
  });

  testWidgets('OFF: the truck step has its old icons and no catalog link', (t) async {
    await openWizard(t);
    expect(find.byKey(const ValueKey('wzTruck_14ft')), findsOneWidget);
    expect(find.byKey(const ValueKey('wzSeeAllVehicles')), findsNothing);
    expect(find.byType(VehicleTypeArt), findsNothing);
  });

  testWidgets('ON: drawings on the trucks, and a vehicle chosen in the catalog is selected in the booking', (t) async {
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.vehicleCatalog: true});
    await openWizard(t);
    expect(find.byType(VehicleTypeArt), findsWidgets);
    await t.tap(find.byKey(const ValueKey('wzSeeAllVehicles')));
    await t.pumpAndSettle();
    expect(find.byType(VehicleCatalogScreen), findsOneWidget);
    await t.scrollUntilVisible(find.byKey(const ValueKey('vc_icv_19ft')), 200, scrollable: find.byType(Scrollable).first);
    await t.tap(find.byKey(const ValueKey('vc_icv_19ft')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('vcPick')));
    await t.pumpAndSettle();
    expect(find.byType(VehicleCatalogScreen), findsNothing);
    expect(find.byType(BookWizardScreen), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('wzTruck_19ft')), matching: find.byIcon(Icons.check_circle_rounded)), findsOneWidget);
  });

  testWidgets('ON: a vehicle the booking does not offer yet is explained, not selected', (t) async {
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.vehicleCatalog: true});
    await openWizard(t);
    await t.tap(find.byKey(const ValueKey('wzSeeAllVehicles')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('vc_e_loader')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('vcPick')));
    await t.pump();
    expect(find.text(T.get('vcuNotBookable', AppLanguage.english)), findsOneWidget);
    expect(find.byType(VehicleSpecScreen), findsOneWidget);
  });

  testWidgets('the bid card shows the vehicle only when it is given one', (t) async {
    Widget card(Widget? vehicle) => MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: Scaffold(body: SingleChildScrollView(child: BidCard(driverName: 'Ramesh', pricePaise: 2400000, vehicle: vehicle))),
        );
    await t.runAsync(() => VehicleCatalog.load());
    await t.pumpWidget(card(null));
    expect(find.byType(VehicleTypeArt), findsNothing);
    await t.pumpWidget(card(const VehicleTypeArt('14ft', width: 120)));
    await t.pumpAndSettle();
    expect(find.byType(VehicleArt), findsOneWidget);
  });

  testWidgets('a type that is not in the catalog keeps an empty box of the same size', (t) async {
    await t.runAsync(() => VehicleCatalog.load());
    await t.pumpWidget(const MaterialApp(home: Center(child: VehicleTypeArt('Spaceship', width: 120))));
    await t.pumpAndSettle();
    expect(find.byType(VehicleArt), findsNothing);
    expect(t.getSize(find.byType(VehicleTypeArt)), const Size(120, 45));
  });

  test('stored types find their catalog entry', () {
    final all = [
      for (final id in ['lcv_14ft', 'box_32ft_sxl']) VehicleSpec(id: id, group: 'lcv', axles: const [2, 4], lengthFt: 14, widthFt: 6, heightFt: 6, minTons: 1, maxTons: 4, goods: const ['fmcg'], bodies: const ['open'], priceBand: 2, legacyId: id == 'lcv_14ft' ? '14ft' : '32ft'),
    ];
    expect(VehicleCatalog.forType(all, '14ft')!.id, 'lcv_14ft');
    expect(VehicleCatalog.forType(all, 'box_32ft_sxl')!.id, 'box_32ft_sxl');
    expect(VehicleCatalog.forType(all, 'nothing'), isNull);
  });
}
