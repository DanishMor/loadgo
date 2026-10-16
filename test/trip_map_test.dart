import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/maps/trip_map.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/theme/app_theme.dart';

class _FakeRenderer implements TripMapRenderer {
  TripMapData? last;
  @override
  Widget build(BuildContext context, TripMapData data) {
    last = data;
    return Container(key: const ValueKey('fakeMap'), color: Colors.grey);
  }
}

Map<String, Object?> _doc({GeoPoint? at, String pickup = 'Delhi', String drop = 'Jaipur'}) => {
      'customerId': 'c1', 'driverId': 'd1', 'status': 'in_transit', 'pickup': pickup, 'drop': drop, 'loadId': 'l', 'vehicleId': 'v',
      'cargoType': 'FMCG', 'weight': 2, 'vehicleType': '14ft', 'notes': '', 'vehicleNumber': 'N', 'driverName': 'D', 'driverPhone': '1',
      'timeline': <String, Object?>{}, 'lastKnownLocation': at, 'locationUpdatedAt': at == null ? null : Timestamp.now(),
    };

void main() {
  late FakeFirebaseFirestore db;
  late _FakeRenderer renderer;

  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'c1');
    renderer = _FakeRenderer();
    TripMapScreen.renderer = renderer;
    languageNotifier.value = AppLanguage.english;
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.maps: true});
  });
  tearDown(() {
    FeaturesService.reset();
    TripMapScreen.renderer = const GoogleTripMapRenderer();
  });

  Widget app(String id) => MaterialApp(theme: AppTheme.build(Brightness.light), home: TripMapScreen(key: ValueKey(id), bookingId: id));

  test('the points come from the city table and the shared position; unknown places are left out', () {
    final b = Booking.fromMap('b1', _doc(at: const GeoPoint(27.5, 76.5), drop: 'Nowhereville'));
    final d = TripMapData.of(b);
    expect(d.pickup!.lat, closeTo(28.61, 0.01));
    expect(d.drop, isNull);
    expect(d.driver, (lat: 27.5, lng: 76.5));
    expect(d.hasAny, isTrue);
    expect(TripMapData.of(Booking.fromMap('b2', _doc(pickup: 'x', drop: 'y'))).hasAny, isFalse);
  });

  testWidgets('the map shows the trip and follows the driver as the position changes', (tester) async {
    await db.collection('bookings').doc('b1').set(_doc(at: const GeoPoint(27.5, 76.5)));
    await tester.pumpWidget(app('b1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fakeMap')), findsOneWidget);
    expect(renderer.last!.driver, (lat: 27.5, lng: 76.5));
    expect(find.text('Driver'), findsOneWidget);
    await tester.runAsync(() => db.collection('bookings').doc('b1').update({'lastKnownLocation': const GeoPoint(27.0, 76.0)}));
    await tester.pumpAndSettle();
    expect(renderer.last!.driver, (lat: 27.0, lng: 76.0));
  });

  testWidgets('no shared position: the legend says so; no known place at all: a calm note', (tester) async {
    await db.collection('bookings').doc('b1').set(_doc());
    await tester.pumpWidget(app('b1'));
    await tester.pumpAndSettle();
    expect(find.text('Not shared yet'), findsOneWidget);
    await db.collection('bookings').doc('b2').set(_doc(pickup: 'x', drop: 'y'));
    await tester.pumpWidget(app('b2'));
    await tester.pumpAndSettle();
    expect(find.text('The map is not available for this trip.'), findsOneWidget);
    expect(find.byKey(const ValueKey('fakeMap')), findsNothing);
  });

  test('the switch decides whether the entry button exists', () {
    expect(TripMapScreen.available, isTrue);
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.maps: false});
    expect(TripMapScreen.available, isFalse);
  });
}
