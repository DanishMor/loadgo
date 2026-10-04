import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/logistics.dart';
import '../matching/load_ranker.dart';
import '../models/booking.dart';
import '../models/vehicle.dart';
import 'backend.dart';
import 'vehicle_service.dart';

/// Data for the matching features: favourite routes, the driver's context
/// for the ranker, the vehicle count shown to customers and the "new loads"
/// badge.
class MatchService {
  MatchService._();

  static const maxFavourites = 20;
  static const _seenKey = 'loads_last_seen_ms';

  static CollectionReference<Map<String, dynamic>> get _routes =>
      Backend.db.collection('users').doc(Backend.requireUid()).collection('favourite_routes');

  // ---- favourite routes ----

  static Stream<List<FavouriteRoute>> watchFavourites() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return Backend.db.collection('users').doc(uid).collection('favourite_routes').snapshots().map((s) => [
          for (final d in s.docs)
            FavouriteRoute(id: d.id, pickup: d.data()['pickup'] as String? ?? '', drop: d.data()['drop'] as String? ?? ''),
        ]);
  }

  /// Returns false when the list is full (and the route is new).
  static Future<bool> addFavourite(String pickup, String drop) async {
    final p = pickup.trim(), d = drop.trim();
    if (p.length < 2 || d.length < 2) throw ArgumentError('Route needs a pickup and a drop');
    final id = FavouriteRoute.idFor(p, d);
    final existing = await _routes.get();
    if (existing.docs.length >= maxFavourites && !existing.docs.any((x) => x.id == id)) return false;
    await _routes.doc(id).set({'pickup': p, 'drop': d, 'createdAt': FieldValue.serverTimestamp()});
    return true;
  }

  static Future<void> removeFavourite(String id) => _routes.doc(id).delete();

  // ---- driver context ----

  /// Everything [LoadRanker] needs about the signed-in driver.
  static Future<DriverContext> driverContext({DateTime? now}) async {
    final uid = Backend.requireUid();
    final results = await Future.wait([
      VehicleService.fetchMyActive(),
      Backend.db.collection('users').doc(uid).get(),
      Backend.db.collection('bookings').where('driverId', isEqualTo: uid).get(),
      _routes.get(),
    ]);
    final vehicles = results[0] as List<Vehicle>;
    final user = (results[1] as DocumentSnapshot<Map<String, dynamic>>).data() ?? const {};
    final bookings = [for (final d in (results[2] as QuerySnapshot<Map<String, dynamic>>).docs) Booking.fromDoc(d)];
    final favourites = [
      for (final d in (results[3] as QuerySnapshot<Map<String, dynamic>>).docs)
        FavouriteRoute(id: d.id, pickup: d.data()['pickup'] as String? ?? '', drop: d.data()['drop'] as String? ?? ''),
    ];

    final active = bookings.where((b) => b.status != BookingStatus.delivered && b.status != BookingStatus.cancelled).toList();
    final delivered = bookings.where((b) => b.status == BookingStatus.delivered).toList()
      ..sort((a, b) => (b.timeline[BookingStatus.delivered] ?? DateTime(2000)).compareTo(a.timeline[BookingStatus.delivered] ?? DateTime(2000)));
    return DriverContext(
      vehicles: vehicles,
      verified: user['verified'] == true,
      anchorPlace: active.isNotEmpty ? active.first.drop : (delivered.isNotEmpty ? delivered.first.drop : null),
      anchorIsActiveTrip: active.isNotEmpty,
      favourites: favourites,
      now: now ?? DateTime.now(),
    );
  }

  // ---- customer: matching vehicles ----

  /// Free vehicles of [vehicleType] able to carry [weight] tonnes.
  /// (Driver verification is private to the driver, so it is not counted.)
  static Future<int> countMatchingVehicles({required String vehicleType, required num weight, DateTime? now}) async {
    final snap = await Backend.db
        .collection('vehicles')
        .where('type', isEqualTo: vehicleType)
        .where('status', isEqualTo: VehicleStatus.active)
        .limit(300)
        .get();
    return LoadRanker.countMatchingVehicles(snap.docs.map(Vehicle.fromDoc),
        vehicleType: vehicleType, weight: weight, now: now ?? DateTime.now());
  }

  // ---- new loads badge ----

  static Future<DateTime?> lastSeenLoads() async {
    try {
      final ms = (await SharedPreferences.getInstance()).getInt(_seenKey);
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  static Future<void> markLoadsSeen([DateTime? at]) async {
    try {
      await (await SharedPreferences.getInstance()).setInt(_seenKey, (at ?? DateTime.now()).millisecondsSinceEpoch);
    } catch (_) {}
  }
}
