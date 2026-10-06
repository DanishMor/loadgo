import 'package:flutter/foundation.dart';

import '../services/backend.dart';

/// Thresholds of the rule-based risk checks (BE13). Admins edit them as JSON
/// in Admin > Config > Risk rules (`config/risk`); missing or odd values fall
/// back to the defaults, and every value is kept inside a sane range.
class RiskConfig {
  /// A load at or above this many paise writes a `high_value` signal.
  final int highValuePaise;

  /// Score at or above which a user is suggested for review.
  final int reviewScore;

  /// Score at or above which the bulk "hold" button pre-selects a user (F14).
  final int holdScore;

  /// Cancellations from which a user is flagged.
  final int cancelFlag;

  /// Loads posted in 24 hours: warning level and burst level (F7).
  final int burstWarnLoads24h;
  final int burstLoads24h;

  /// New devices of one account in 24 hours that raise `many_devices` (F5).
  final int manyDevices24h;

  /// Accounts on one device that make a cluster.
  final int deviceCluster;

  /// Phone changes in the last 30 days that count as profile churn (F7).
  final int phoneChanges30d;

  const RiskConfig({
    this.highValuePaise = 5000000,
    this.reviewScore = 50,
    this.holdScore = 70,
    this.cancelFlag = 3,
    this.burstWarnLoads24h = 5,
    this.burstLoads24h = 10,
    this.manyDevices24h = 3,
    this.deviceCluster = 3,
    this.phoneChanges30d = 2,
  });

  static const defaults = RiskConfig();

  static int _int(Object? v, int fallback, int min, int max) {
    final n = v is num ? v.round() : fallback;
    return n.clamp(min, max);
  }

  factory RiskConfig.fromMap(Map<String, dynamic>? m) {
    final d = m ?? const {};
    const f = RiskConfig.defaults;
    return RiskConfig(
      highValuePaise: _int(d['highValuePaise'], f.highValuePaise, 100000, 1000000000),
      reviewScore: _int(d['reviewScore'], f.reviewScore, 10, 500),
      holdScore: _int(d['holdScore'], f.holdScore, 10, 500),
      cancelFlag: _int(d['cancelFlag'], f.cancelFlag, 1, 50),
      burstWarnLoads24h: _int(d['burstWarnLoads24h'], f.burstWarnLoads24h, 1, 500),
      burstLoads24h: _int(d['burstLoads24h'], f.burstLoads24h, 2, 1000),
      manyDevices24h: _int(d['manyDevices24h'], f.manyDevices24h, 2, 50),
      deviceCluster: _int(d['deviceCluster'], f.deviceCluster, 2, 50),
      phoneChanges30d: _int(d['phoneChanges30d'], f.phoneChanges30d, 1, 20),
    );
  }

  Map<String, dynamic> toMap() => {
        'highValuePaise': highValuePaise,
        'reviewScore': reviewScore,
        'holdScore': holdScore,
        'cancelFlag': cancelFlag,
        'burstWarnLoads24h': burstWarnLoads24h,
        'burstLoads24h': burstLoads24h,
        'manyDevices24h': manyDevices24h,
        'deviceCluster': deviceCluster,
        'phoneChanges30d': phoneChanges30d,
      };
}

/// The active thresholds, loaded with the other config documents.
class RiskConfigStore {
  RiskConfigStore._();

  static final ValueNotifier<RiskConfig> notifier = ValueNotifier(RiskConfig.defaults);

  static RiskConfig get current => notifier.value;

  static Future<void> refresh() async {
    try {
      final snap = await Backend.db.collection('config').doc('risk').get();
      notifier.value = RiskConfig.fromMap(snap.data());
    } catch (_) {
      // Keep the current thresholds when offline or signed out.
    }
  }
}
