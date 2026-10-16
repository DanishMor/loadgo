import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/adapters/google_maps_provider.dart';
import 'package:transport_app/core/adapters/maps_adapter.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/maps/road_distance.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/services/server_actions.dart';

class _Server implements ServerGateway {
  Object? error;
  Map<String, dynamic> answer = {'meters': 281400, 'seconds': 18000};
  final calls = <Map<String, Object?>>[];

  @override
  Future<Map<String, dynamic>> call(String name, Map<String, Object?> data) async {
    expect(name, 'mapsRoute');
    calls.add(data);
    if (error != null) throw error!;
    return answer;
  }
}

class _Provider implements MapsProvider {
  int calls = 0;
  RouteInfo? answer = const RouteInfo(281400, 18000);
  @override
  Future<GeoPoint2?> geocode(String place) async => null;
  @override
  Future<RouteInfo?> route(GeoPoint2 from, GeoPoint2 to) async {
    calls++;
    return answer;
  }
}

void main() {
  late _Provider p;
  setUp(() {
    RoadDistance.reset();
    GoogleMapsProvider.outOfTurnsToday = false;
    p = _Provider();
    RoadDistance.provider = p;
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.maps: true});
  });
  tearDown(FeaturesService.reset);

  test('switch off: no call and no distance, the city table stays in charge', () async {
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.maps: false});
    expect(await RoadDistance.prefetch(['Delhi', 'Jaipur']), isFalse);
    expect(RoadDistance.kmFor(['Delhi', 'Jaipur']), isNull);
    expect(p.calls, 0);
  });

  test('a known pair is asked once, rounded up to whole km, and then served from memory', () async {
    expect(RoadDistance.kmFor(['Delhi', 'Jaipur']), isNull);
    expect(await RoadDistance.prefetch(['Delhi', 'Jaipur']), isTrue);
    expect(RoadDistance.kmFor(['Delhi', 'Jaipur']), 282);
    expect(await RoadDistance.prefetch(['Delhi', 'Jaipur']), isFalse);
    expect(p.calls, 1);
  });

  test('a route with stops adds the legs, and needs every leg', () async {
    await RoadDistance.prefetch(['Delhi', 'Jaipur', 'Mumbai']);
    expect(p.calls, 2);
    expect(RoadDistance.kmFor(['Delhi', 'Jaipur', 'Mumbai']), 564);
    expect(RoadDistance.kmFor(['Delhi', 'Jaipur', 'Pune']), isNull);
  });

  test('unknown places and a failed answer keep the old distance and are not asked again', () async {
    expect(await RoadDistance.prefetch(['Nowhereville', 'Jaipur']), isFalse);
    expect(p.calls, 0);
    p.answer = null;
    expect(await RoadDistance.prefetch(['Delhi', 'Pune']), isFalse);
    expect(RoadDistance.kmFor(['Delhi', 'Pune']), isNull);
    await RoadDistance.prefetch(['Delhi', 'Pune']);
    expect(p.calls, 1, reason: 'one try per pair, so a broken server is not hammered');
  });

  test('the provider turns the server answer into a route, junk into null, and remembers the daily limit', () async {
    final s = _Server();
    final g = GoogleMapsProvider(s);
    final r = await g.route(const GeoPoint2(28.6, 77.2), const GeoPoint2(26.9, 75.8));
    expect(r!.meters, 281400);
    expect(s.calls.single['from'], {'lat': 28.6, 'lng': 77.2});
    s.answer = {'meters': -5};
    expect(await g.route(const GeoPoint2(1, 1), const GeoPoint2(2, 2)), isNull);
    s.answer = {'meters': 'far'};
    expect(await g.route(const GeoPoint2(1, 1), const GeoPoint2(2, 2)), isNull);
    s.error = FirebaseFunctionsException(code: 'resource-exhausted', message: 'too many');
    expect(await g.route(const GeoPoint2(1, 1), const GeoPoint2(2, 2)), isNull);
    expect(GoogleMapsProvider.limited, isTrue);
    final before = s.calls.length;
    s.error = null;
    s.answer = {'meters': 1000, 'seconds': 10};
    expect(await g.route(const GeoPoint2(1, 1), const GeoPoint2(2, 2)), isNull, reason: 'no more asking today');
    expect(s.calls.length, before);
    expect(await g.geocode('Delhi'), isNull);
  });
}
