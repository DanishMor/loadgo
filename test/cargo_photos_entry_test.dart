import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/driver/available_loads_view.dart';
import 'package:transport_app/driver/trip_proof_dialogs.dart';

/// E19c: the driver's entry points of cargoPhotos (trip step photos, goods photos on a load card).
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'drv1');
    FeaturesService.reset();
    languageNotifier.value = AppLanguage.english;
  });
  tearDown(FeaturesService.reset);

  String en(String k) => T.get(k, AppLanguage.english);

  Widget host(Widget child) => LanguageScope(
        notifier: languageNotifier,
        child: MaterialApp(theme: AppTheme.build(Brightness.light, style: ThemeStyle.signature), home: Scaffold(body: child)),
      );

  Future<void> openDialog(WidgetTester t, bool pickup) async {
    await t.pumpWidget(host(Builder(
      builder: (context) => TextButton(
        onPressed: () => pickup ? askPickupProof(context, bookingId: 'B1') : askDeliveryProof(context, bookingId: 'B1'),
        child: const Text('open'),
      ),
    )));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  testWidgets('trip steps: seal photo at pickup and damage photo at delivery only with cargoPhotos on', (t) async {
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.photoUploads: true});
    await openDialog(t, true);
    expect(find.text(en('photoKind_pickup')), findsOneWidget);
    expect(find.text(en('photoKind_seal')), findsNothing);
    Navigator.of(t.element(find.byType(AlertDialog))).pop();
    await t.pumpAndSettle();

    FeaturesService.notifier.value = const Features(flags: {FeatureKey.photoUploads: true, FeatureKey.cargoPhotos: true});
    await openDialog(t, true);
    expect(find.text(en('photoKind_seal')), findsOneWidget);
    Navigator.of(t.element(find.byType(AlertDialog))).pop();
    await t.pumpAndSettle();
    await openDialog(t, false);
    expect(find.text(en('photoKind_damage')), findsOneWidget);
  });

  testWidgets('load card: the goods photo icon needs cargoPhotos and photoUploads', (t) async {
    final load = Load(id: 'L1', shipperId: 'cust1', pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: 2, vehicleType: '14ft', budget: null, pickupDate: DateTime(2030), notes: '', status: 'open');
    await t.pumpWidget(host(AcceptLoadButton(load: load)));
    expect(find.byKey(const ValueKey('cgView_L1')), findsNothing);
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.cargoPhotos: true});
    await t.pumpWidget(host(AcceptLoadButton(key: const ValueKey(1), load: load)));
    expect(find.byKey(const ValueKey('cgView_L1')), findsNothing);
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.cargoPhotos: true, FeatureKey.photoUploads: true});
    await t.pumpWidget(host(AcceptLoadButton(key: const ValueKey(2), load: load)));
    expect(find.byKey(const ValueKey('cgView_L1')), findsOneWidget);
  });
}
