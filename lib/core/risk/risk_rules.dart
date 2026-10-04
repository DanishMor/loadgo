import 'dart:math';

import '../models/risk.dart';

/// Rule-based risk checks (no machine learning, no server). They only
/// suggest: an admin decides. TODO(functions): run them on a schedule and
/// open fraud cases automatically.
class RiskRules {
  RiskRules._();

  /// A load or payment at or above this many paise is "high value" (Rs 50,000)
  /// and writes a `high_value` risk signal for admins.
  static const highValuePaise = 5000000;

  /// Score at or above which a user is suggested for manual review.
  static const reviewScore = 50;

  static bool isHighValue(int totalPaise) => totalPaise >= highValuePaise;

  /// Behavioural score: cancellations, open reports, new-device signals,
  /// expired papers and the current risk tier. Higher = look sooner.
  static ({int score, List<String> reasons}) score({
    required int cancelCount,
    required int openReports,
    int newDevicesLast7Days = 0,
    int expiredPapers = 0,
    String tier = RiskTier.normal,
  }) {
    var s = 0;
    final why = <String>[];
    if (cancelCount >= 5) {
      s += 40;
      why.add('cancels_5');
    } else if (cancelCount >= cancelFlagThreshold) {
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

  static bool suggestReview(int score) => score >= reviewScore;

  /// [n] accounts picked at random from [candidates] for a spot check (R8).
  static List<T> randomSample<T>(List<T> candidates, int n, {int? seed}) {
    final list = List<T>.of(candidates);
    list.shuffle(seed == null ? null : _Seeded(seed));
    return list.take(n).toList();
  }
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
