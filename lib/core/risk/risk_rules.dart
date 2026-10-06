import 'dart:math';

import '../models/risk.dart';
import '../models/vehicle.dart';
import 'risk_config.dart';

/// Rule-based risk checks (no machine learning, no server). They only
/// suggest: an admin decides. TODO(functions): run them on a schedule and
/// open fraud cases automatically.
class RiskRules {
  RiskRules._();

  /// A load or payment at or above this many paise is "high value" (Rs 50,000)
  /// and writes a `high_value` risk signal for admins.
  /// The thresholds live in `config/risk` ([RiskConfig], BE13); these are the defaults.
  static const highValuePaise = 5000000;

  /// Default score at or above which a user is suggested for manual review.
  static const reviewScore = 50;

  static RiskConfig get _cfg => RiskConfigStore.current;

  static bool isHighValue(int totalPaise, {RiskConfig? config}) => totalPaise >= (config ?? _cfg).highValuePaise;

  /// Behavioural score: cancellations, open reports, new-device signals,
  /// expired papers and the current risk tier. Higher = look sooner.
  static ({int score, List<String> reasons}) score({
    required int cancelCount,
    required int openReports,
    int newDevicesLast7Days = 0,
    int expiredPapers = 0,
    String tier = RiskTier.normal,
    int loadsLast24h = 0,
    int phoneChanges30d = 0,
    int manyDeviceSignals30d = 0,
    int gpsMismatches30d = 0,
    RiskConfig? config,
  }) {
    final cfg = config ?? _cfg;
    var s = 0;
    final why = <String>[];
    // F7: bursts of loads, repeated phone changes, many devices in a day,
    // GPS far from the booked city.
    if (loadsLast24h >= cfg.burstLoads24h) {
      s += 20;
      why.add('booking_burst');
    } else if (loadsLast24h >= cfg.burstWarnLoads24h) {
      s += 10;
      why.add('booking_burst_warn');
    }
    if (phoneChanges30d >= cfg.phoneChanges30d) {
      s += 20;
      why.add('profile_changes');
    }
    if (manyDeviceSignals30d > 0) {
      s += 15;
      why.add('many_devices_24h');
    }
    if (gpsMismatches30d >= 2) {
      s += 15;
      why.add('gps_mismatch');
    }
    if (cancelCount >= 5) {
      s += 40;
      why.add('cancels_5');
    } else if (cancelCount >= cfg.cancelFlag) {
      s += 20;
      why.add('cancels_3');
    }
    if (openReports > 0) {
      s += (openReports * 15).clamp(0, 45);
      why.add('open_reports');
    }
    if (newDevicesLast7Days >= 2) {
      s += 20;
      why.add('many_new_devices');
    } else if (newDevicesLast7Days == 1) {
      s += 5;
      why.add('new_device');
    }
    if (expiredPapers > 0) {
      s += 15;
      why.add('expired_papers');
    }
    switch (tier) {
      case RiskTier.review:
        s += 10;
      case RiskTier.restricted:
        s += 30;
      case RiskTier.suspended:
        s += 50;
    }
    return (score: s, reasons: why);
  }

  static bool suggestReview(int score, {RiskConfig? config}) => score >= (config ?? _cfg).reviewScore;

  /// F14: the bulk hold button pre-selects users at or above this score.
  static bool suggestHold(int score, {RiskConfig? config}) => score >= (config ?? _cfg).holdScore;

  static final _plate = RegExp(r'^([A-Z]{2})[0-9]{1,2}[A-Z]{0,3}[0-9]{4}$');

  /// F3: things that do not add up between a vehicle and its RC. The RC number
  /// is normally the registration number, so an RC that looks like a plate of
  /// another number or another state is suspicious. Only a hint for admins;
  /// the portal check (Vahan) needs a provider (LATER(paid)).
  static List<String> vehicleAnomalies(Vehicle v) {
    final number = v.number.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    final rc = v.rcNumber.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    final a = _plate.firstMatch(number);
    final b = _plate.firstMatch(rc);
    if (a == null || b == null) return const [];
    if (a.group(1) != b.group(1)) return const ['rc_state_differs'];
    if (number != rc) return const ['rc_number_differs'];
    return const [];
  }

  /// F3: more vehicles than one driver can run, outside a fleet account.
  static const maxVehiclesPerDriver = 5;

  /// A name for comparing accounts: lower case letters and single spaces.
  static String nameKey(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{M}\s]', unicode: true), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  /// F1: other accounts that look like [uid]: on a device the account used,
  /// or with the same name. [devicesByUid] holds the device ids of every
  /// account in play, [sameName] the uids with an equal [nameKey].
  static List<DuplicateCandidate> duplicates(String uid, Map<String, Set<String>> devicesByUid, Set<String> sameName) {
    final mine = devicesByUid[uid] ?? const <String>{};
    final out = <DuplicateCandidate>[];
    final others = {...devicesByUid.keys, ...sameName}..remove(uid);
    for (final o in others) {
      final shared = (devicesByUid[o] ?? const <String>{}).intersection(mine);
      final reasons = [if (shared.isNotEmpty) 'shared_device', if (sameName.contains(o)) 'same_name'];
      if (reasons.isNotEmpty) out.add(DuplicateCandidate(o, reasons, shared.length));
    }
    out.sort((a, b) => b.reasons.length != a.reasons.length ? b.reasons.length.compareTo(a.reasons.length) : b.sharedDevices.compareTo(a.sharedDevices));
    return out;
  }

  /// [n] accounts picked at random from [candidates] for a spot check (R8).
  static List<T> randomSample<T>(List<T> candidates, int n, {int? seed}) {
    final list = List<T>.of(candidates);
    list.shuffle(seed == null ? null : _Seeded(seed));
    return list.take(n).toList();
  }
}

/// An account that may be the same person as another (F1).
class DuplicateCandidate {
  final String uid;
  final List<String> reasons;
  final int sharedDevices;
  const DuplicateCandidate(this.uid, this.reasons, this.sharedDevices);
}

class _Seeded implements Random {
  final Random _r;
  _Seeded(int seed) : _r = Random(seed);
  @override
  bool nextBool() => _r.nextBool();
  @override
  double nextDouble() => _r.nextDouble();
  @override
  int nextInt(int max) => _r.nextInt(max);
}
