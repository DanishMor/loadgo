import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/logistics.dart';
import '../../core/dispatch/dispatch_models.dart';
import '../../core/drafts/smart_defaults.dart';
import '../../core/maps/road_distance.dart';
import '../../core/models/vehicle_type.dart';
import '../../core/pricing/fare_calculator.dart';
import '../../core/scheduling/schedule.dart';
import '../../core/services/backend.dart';
import '../../core/services/pricing_service.dart';

/// The five questions of the new booking (U19), in order.
enum WizardStep { route, goods, truck, price, review }

/// What the person has answered so far. A plain value: every check and every number comes from here, so the screen
/// only draws it and a test can run the whole booking without a widget.
class WizardDraft {
  final String pickup;
  final String drop;
  final String cargo;

  /// Weight in tonnes; null until chosen.
  final double? weightTons;
  final String? vehicleType;
  final LoadMode mode;

  /// The price the customer chooses, in paise; null until chosen.
  final int? pricePaise;
  final DateTime? scheduledAt;
  final int step;

  const WizardDraft({
    this.pickup = '',
    this.drop = '',
    this.cargo = 'General',
    this.weightTons,
    this.vehicleType,
    this.mode = LoadMode.instant,
    this.pricePaise,
    this.scheduledAt,
    this.step = 0,
  });

  WizardDraft copyWith({
    String? pickup,
    String? drop,
    String? cargo,
    double? Function()? weightTons,
    String? Function()? vehicleType,
    LoadMode? mode,
    int? Function()? pricePaise,
    DateTime? Function()? scheduledAt,
    int? step,
  }) =>
      WizardDraft(
        pickup: pickup ?? this.pickup,
        drop: drop ?? this.drop,
        cargo: cargo ?? this.cargo,
        weightTons: weightTons == null ? this.weightTons : weightTons(),
        vehicleType: vehicleType == null ? this.vehicleType : vehicleType(),
        mode: mode ?? this.mode,
        pricePaise: pricePaise == null ? this.pricePaise : pricePaise(),
        scheduledAt: scheduledAt == null ? this.scheduledAt : scheduledAt(),
        step: step ?? this.step,
      );

  static const lastStep = 4;
  static const minWeight = 0.5;
  static const maxWeight = 40.0;

  List<String> get route => [pickup, drop];

  /// Road km of the route: the table of roads when it has the pair, else the straight line of the cities x 1.25.
  int? get km => RoadDistance.kmFor(route) ?? PricingService.estimateRouteKm(route);

  /// The fare estimate of the chosen truck on this route, or null when the distance or the truck is unknown.
  FareBreakdown? get quote {
    final k = km, v = vehicleType;
    if (k == null || v == null) return null;
    return PricingService.quote(vehicleType: v, distanceKm: k, at: scheduledAt);
  }

  int? get estimatePaise => quote?.total;

  /// The price that is used: the chosen one, else the estimate rounded to whole ten rupees.
  int? get effectivePricePaise => pricePaise ?? roundTo10Rupees(estimatePaise);

  static int? roundTo10Rupees(int? paise) => paise == null ? null : ((paise + 500) ~/ 1000) * 1000;

  /// The l10n key of what is missing on [step], or null when the step is complete.
  String? stepError(int step, {DateTime? now, ScheduleRules? rules}) {
    switch (step) {
      case 0:
        return pickup.trim().length < 2 || drop.trim().length < 2 ? 'wzNeedRoute' : null;
      case 1:
        final w = weightTons;
        return cargo.trim().isEmpty || w == null || w < minWeight || w > maxWeight ? 'wzNeedGoods' : null;
      case 2:
        final v = vehicleType;
        if (v == null) return 'wzNeedTruck';
        return null;
      case 3:
        final p = effectivePricePaise;
        if (p == null || p <= 0 || p > 100000000) return 'wzNeedPrice';
        if (mode == LoadMode.scheduled) {
          final at = scheduledAt;
          if (at == null) return 'wzNeedDate';
          final problem = Schedule.check(at, now ?? DateTime.now(), rules ?? PricingService.config.schedule);
          if (problem != null) return problem == ScheduleProblem.tooSoon ? 'wzDateTooSoon' : 'wzDateTooFar';
        }
        return null;
      default:
        return null;
    }
  }

  /// The first step that is not complete, or null when the whole booking is ready.
  int? firstIncomplete({DateTime? now, ScheduleRules? rules}) {
    for (var s = 0; s <= 3; s++) {
      if (stepError(s, now: now, rules: rules) != null) return s;
    }
    return null;
  }

  /// The smallest active truck that carries [weightTons], as in the old form (docs: SmartDefaults).
  static VehicleTypeInfo? suggest(double? weightTons, Iterable<VehicleTypeInfo> types) => SmartDefaults.suggestVehicle(weightTons, types);

  /// The whole rupees of the price for `LoadService.post(budget:)`.
  num? get budgetRupees {
    final p = effectivePricePaise;
    return p == null ? null : (p / 100).round();
  }

  Map<String, Object?> toJson() => {
        'pickup': pickup,
        'drop': drop,
        'cargo': cargo,
        'weight': weightTons,
        'vehicle': vehicleType,
        'mode': mode.value,
        'price': pricePaise,
        'at': scheduledAt?.toIso8601String(),
        'step': step,
      };

  static WizardDraft fromJson(Object? j) {
    if (j is! Map) return const WizardDraft();
    String s(Object? v) => v is String ? v : '';
    final w = j['weight'];
    final p = j['price'];
    final step = j['step'];
    return WizardDraft(
      pickup: s(j['pickup']).length > 200 ? '' : s(j['pickup']),
      drop: s(j['drop']).length > 200 ? '' : s(j['drop']),
      cargo: cargoTypes.contains(j['cargo']) ? j['cargo'] as String : 'General',
      weightTons: w is num && w >= minWeight && w <= maxWeight ? w.toDouble() : null,
      vehicleType: j['vehicle'] is String && (j['vehicle'] as String).isNotEmpty && (j['vehicle'] as String).length <= 40 ? j['vehicle'] as String : null,
      mode: LoadMode.fromValue(j['mode']),
      pricePaise: p is int && p > 0 && p <= 100000000 ? p : null,
      scheduledAt: j['at'] is String ? DateTime.tryParse(j['at'] as String) : null,
      step: step is int ? step.clamp(0, lastStep) : 0,
    );
  }

  bool get isWorthSaving => pickup.trim().isNotEmpty || drop.trim().isNotEmpty || weightTons != null || vehicleType != null;
}

/// The draft is kept on the phone for 7 days, so closing the app in the middle of a booking loses nothing.
class WizardDraftStore {
  WizardDraftStore._();

  static String get _key => 'wizard_draft_${Backend.uid ?? 'anon'}';
  static const maxAge = Duration(days: 7);

  static Future<WizardDraft?> load({DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      final saved = DateTime.tryParse(m['savedAt'] is String ? m['savedAt'] as String : '');
      if (saved == null || (now ?? DateTime.now()).difference(saved) > maxAge) {
        await prefs.remove(_key);
        return null;
      }
      final d = WizardDraft.fromJson(m['draft']);
      return d.isWorthSaving ? d : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(WizardDraft d, {DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!d.isWorthSaving) {
        await prefs.remove(_key);
        return;
      }
      await prefs.setString(_key, jsonEncode({'savedAt': (now ?? DateTime.now()).toIso8601String(), 'draft': d.toJson()}));
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      await (await SharedPreferences.getInstance()).remove(_key);
    } catch (_) {}
  }
}
