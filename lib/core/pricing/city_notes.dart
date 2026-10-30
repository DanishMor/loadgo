import 'package:cloud_firestore/cloud_firestore.dart';

import '../adapters/adapters.dart';
import '../services/backend.dart';
import '../services/features_service.dart';
import '../vehicles/vehicle_catalog.dart';
import 'cities.dart';

/// E33 (flag cityNotes): notes an admin writes about a city, such as hours when trucks may not enter. The app
/// shows the admin's words as they are and adds no claim of its own. Stored in `config/city_notes`
/// ({notes: {cityName: text}, updatedAt}), which the existing config rule already covers (super admins write,
/// signed-in people read).
class CityNotes {
  final Map<String, String> notes;
  const CityNotes(this.notes);

  static const maxCities = 100;
  static const maxChars = 300;
  static const empty = CityNotes({});

  /// Defensive: only string notes, trimmed, at most [maxCities] cities and [maxChars] characters each.
  factory CityNotes.fromMap(Map<String, dynamic>? m) {
    final raw = m?['notes'];
    if (raw is! Map) return empty;
    final out = <String, String>{};
    for (final e in raw.entries) {
      if (out.length >= maxCities) break;
      final k = e.key, v = e.value;
      if (k is! String || v is! String) continue;
      final note = v.trim();
      if (k.trim().length < 2 || note.isEmpty) continue;
      out[k.trim()] = note.length > maxChars ? note.substring(0, maxChars) : note;
    }
    return CityNotes(out);
  }

  /// The note for a place the person typed, matched through the city table (aliases count), else by exact name.
  String? noteFor(String place) {
    final city = findCity(place)?.name ?? place.trim();
    for (final e in notes.entries) {
      if (e.key.toLowerCase() == city.toLowerCase()) return e.value;
    }
    return null;
  }

  Map<String, Object> toMap() => {'notes': notes, 'updatedAt': FieldValue.serverTimestamp()};
}

class CityNotesService {
  CityNotesService._();

  static Future<CityNotes>? _cache;

  static DocumentReference<Map<String, dynamic>> get _doc => Backend.db.collection('config').doc('city_notes');

  /// One read per app session; empty on any error.
  static Future<CityNotes> load() => _cache ??= _doc.get().then((s) => CityNotes.fromMap(s.data()), onError: (_) => CityNotes.empty);

  static void reset() => _cache = null;

  /// Super admins only (firestore.rules config).
  static Future<void> save(CityNotes notes) async {
    await _doc.set(notes.toMap());
    _cache = Future.value(notes);
  }
}

/// E33 (flag tollEstimate): expected tolls for a trip in paise from the TollEstimator adapter (real only when the
/// flag is ON and a provider is configured), or null. Approximate and never part of the fare.
class TollLine {
  TollLine._();

  static TollEstimator adapter = const NoTollEstimator();
  static final CostGuard guard = ConnectKit.guard('toll', () => FeaturesService.notifier.value, const ProviderConfig());

  static Future<int?> estimate(String pickup, String drop, String vehicleType, {TollEstimator? via, CostGuard? guardOverride, Future<List<VehicleSpec>> Function()? catalog}) async {
    final a = findCity(pickup), b = findCity(drop);
    if (a == null || b == null || a.name == b.name) return null;
    if ((guardOverride ?? guard).take(Backend.uid ?? 'anon') != null) return null;
    var axles = 2;
    try {
      final spec = VehicleCatalog.forType(await (catalog ?? () => VehicleCatalog.load())(), vehicleType);
      if (spec != null && spec.axles.length >= 2) axles = spec.axles.length;
    } catch (_) {}
    try {
      final paise = await (via ?? adapter).tollPaise(GeoPoint2(a.lat, a.lng), GeoPoint2(b.lat, b.lng), axles: axles);
      return paise == null || paise <= 0 ? null : paise;
    } catch (_) {
      return null;
    }
  }
}
