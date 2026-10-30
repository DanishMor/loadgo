import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/matching/load_ranker.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/vehicle.dart';

final now = DateTime(2026, 10, 5, 10);
Vehicle truck() => const Vehicle(id: 'v1', ownerId: 'd1', number: 'MH12AB1234', type: '20ft', capacity: 10, rcNumber: 'RC', status: 'active');
Load load(String id, String pickup, String drop) => Load(
    id: id, shipperId: 'c1', pickup: pickup, drop: drop, cargoType: 'FMCG', weight: 8, vehicleType: '20ft', budget: 25000, pickupDate: now, notes: '', status: 'open');

/// E35 (flag goingTo): loads on a favourite route driven back rank higher, only with the flag.
void main() {
  const fav = FavouriteRoute(id: 'x', pickup: 'Delhi', drop: 'Mumbai');
  DriverContext ctx({bool homeward = false}) => DriverContext(vehicles: [truck()], favourites: const [fav], anchorPlace: 'Mumbai', now: now, homeward: homeward);

  test('the way back is matched by city (aliases count); the same direction is not', () {
    expect(fav.matchesBack(load('a', 'Bombay', 'New Delhi')), isTrue);
    expect(fav.matchesBack(load('b', 'Delhi', 'Mumbai')), isFalse);
  });

  test('off: no homeward reason and the order is unchanged; on: the way back moves up with its reason', () {
    final back = load('back', 'Mumbai', 'Delhi');
    final other = load('other', 'Mumbai', 'Pune');
    final off = LoadRanker.rank([other, back], ctx());
    expect(off.expand((m) => m.reasons), isNot(contains(MatchReason.homeward)));
    final on = LoadRanker.rank([other, back], ctx(homeward: true));
    expect(on.first.load.id, 'back');
    expect(on.first.reasons, contains(MatchReason.homeward));
    final offBack = off.firstWhere((m) => m.load.id == 'back');
    expect(on.first.score - offBack.score, 20);
  });

  test('a load on the favourite route itself keeps the favourite reason, not both', () {
    final m = LoadRanker.matchFor(load('same', 'Delhi', 'Mumbai'), ctx(homeward: true))!;
    expect(m.reasons, contains(MatchReason.favouriteRoute));
    expect(m.reasons, isNot(contains(MatchReason.homeward)));
  });
}
