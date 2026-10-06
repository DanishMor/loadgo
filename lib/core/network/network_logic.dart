import '../models/load.dart';
import '../pricing/cities.dart';

/// Who may see a driver's position (CH13). Values are stored in
/// `driver_presence.mode` and must stay in sync with firestore.rules.
class LocationMode {
  LocationMode._();
  static const nearby = 'nearby';
  static const connections = 'connections';
  static const tripMembers = 'trip';
  static const hidden = 'hidden';
  static const all = [nearby, connections, tripMembers, hidden];

  /// Modes that put a position in `driver_presence` for other drivers.
  static bool publishes(String mode) => mode == nearby || mode == connections;
}

/// How long one location share lasts (CH14), in hours.
const shareDurationsHours = [1, 8, 24];

/// Document id of the link between two drivers: both uids, sorted.
String pairIdOf(String a, String b) => a.compareTo(b) <= 0 ? '${a}_$b' : '${b}_$a';

/// Position shown to others: about 1 km, never the exact spot.
double roundCoord(double v) => (v * 100).round() / 100;

const groupKinds = ['trip', 'route', 'convoy', 'fleet'];
const maxGroupMembers = 30;

/// A driver another driver can see in the nearby list.
class DriverPresence {
  final String uid;
  final String name;
  final double lat;
  final double lng;
  final String mode;
  final DateTime? sharedUntil;
  const DriverPresence({required this.uid, required this.name, required this.lat, required this.lng, required this.mode, this.sharedUntil});

  bool expired(DateTime now) => sharedUntil == null || !sharedUntil!.isAfter(now);
}

/// Drivers to list: not me, not expired, not already connected, nearest first
/// within [radiusKm]. The expiry is checked here because rules cannot filter a
/// list by time (TODO(functions): scrub expired documents).
List<({DriverPresence driver, double km})> nearbyDrivers(
  Iterable<DriverPresence> all, {
  required double lat,
  required double lng,
  required String myUid,
  required DateTime now,
  Set<String> hide = const {},
  double radiusKm = 100,
}) {
  final out = <({DriverPresence driver, double km})>[];
  for (final d in all) {
    if (d.uid == myUid || hide.contains(d.uid) || d.expired(now) || !LocationMode.publishes(d.mode)) continue;
    final km = haversineKm(lat, lng, d.lat, d.lng);
    if (km <= radiusKm) out.add((driver: d, km: km));
  }
  out.sort((a, b) => a.km.compareTo(b.km));
  return out;
}

/// The load details copied into a message (D14, CH7).
class SharedLoad {
  final String loadId;
  final String pickup;
  final String drop;
  final String cargoType;
  final num weight;
  final String vehicleType;
  final int? budgetPaise;
  const SharedLoad({required this.loadId, required this.pickup, required this.drop, required this.cargoType, required this.weight, required this.vehicleType, this.budgetPaise});

  /// Only public loads go to a group: a restricted load must not leak.
  static bool canShare(Load l) => l.visibility == LoadVisibility.public && l.isOpen;

  factory SharedLoad.fromLoad(Load l) => SharedLoad(
        loadId: l.id,
        pickup: l.pickup,
        drop: l.drop,
        cargoType: l.cargoType,
        weight: l.weight,
        vehicleType: l.vehicleType,
        budgetPaise: l.budget == null ? null : (l.budget! * 100).round(),
      );

  Map<String, Object?> toMap() => {
        'loadId': loadId,
        'pickup': pickup,
        'drop': drop,
        'cargoType': cargoType,
        'weight': weight,
        'vehicleType': vehicleType,
        if (budgetPaise != null) 'budgetPaise': budgetPaise,
      };

  static SharedLoad? fromMap(Object? m) {
    if (m is! Map) return null;
    return SharedLoad(
      loadId: m['loadId'] as String? ?? '',
      pickup: m['pickup'] as String? ?? '',
      drop: m['drop'] as String? ?? '',
      cargoType: m['cargoType'] as String? ?? '',
      weight: m['weight'] as num? ?? 0,
      vehicleType: m['vehicleType'] as String? ?? '',
      budgetPaise: (m['budgetPaise'] as num?)?.round(),
    );
  }
}
