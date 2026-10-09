import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/backend.dart';

/// An unfinished Post Load form kept on this phone (MASTER-6 Task 15). Free:
/// nothing leaves the device. One draft per signed-in person, kept 7 days.
class LoadDraft {
  final String pickup;
  final String drop;
  final String cargoType;
  final String weight;
  final String vehicleType;
  final String budget;
  final String notes;

  /// yyyy-mm-dd or empty.
  final String pickupDate;
  final DateTime savedAt;

  const LoadDraft({
    this.pickup = '',
    this.drop = '',
    this.cargoType = '',
    this.weight = '',
    this.vehicleType = '',
    this.budget = '',
    this.notes = '',
    this.pickupDate = '',
    required this.savedAt,
  });

  static const keepDays = 7;
  static const maxText = 300;

  /// Worth keeping once the person typed a place or a weight.
  bool get isWorthSaving => pickup.trim().length >= 2 || drop.trim().length >= 2 || weight.trim().isNotEmpty;

  bool isExpired(DateTime now) => now.difference(savedAt).inDays >= keepDays;

  Map<String, Object?> toJson() => {
        'pickup': _cut(pickup),
        'drop': _cut(drop),
        'cargoType': _cut(cargoType),
        'weight': _cut(weight),
        'vehicleType': _cut(vehicleType),
        'budget': _cut(budget),
        'notes': _cut(notes),
        'pickupDate': pickupDate,
        'savedAt': savedAt.toIso8601String(),
      };

  static String _cut(String s) => s.length > maxText ? s.substring(0, maxText) : s;

  static LoadDraft? fromJson(Object? raw) {
    if (raw is! Map) return null;
    String s(String k) => raw[k] is String ? raw[k] as String : '';
    final at = DateTime.tryParse(s('savedAt'));
    if (at == null) return null;
    return LoadDraft(
      pickup: s('pickup'),
      drop: s('drop'),
      cargoType: s('cargoType'),
      weight: s('weight'),
      vehicleType: s('vehicleType'),
      budget: s('budget'),
      notes: s('notes'),
      pickupDate: s('pickupDate'),
      savedAt: at,
    );
  }

  DateTime? get pickupDay => pickupDate.isEmpty ? null : DateTime.tryParse(pickupDate);
}

class LoadDraftStore {
  LoadDraftStore._();

  static String get _key => 'load_draft_${Backend.uid ?? 'anon'}';

  /// The saved draft, or null when there is none, it is empty or older than 7 days (then it is removed).
  static Future<LoadDraft?> load({DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      final d = LoadDraft.fromJson(jsonDecode(raw));
      if (d == null || !d.isWorthSaving || d.isExpired(now ?? DateTime.now())) {
        await prefs.remove(_key);
        return null;
      }
      return d;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(LoadDraft d) async {
    if (!d.isWorthSaving) return clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(d.toJson()));
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
