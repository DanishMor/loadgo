import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/risk.dart';
import '../models/vehicle.dart';
import '../risk/risk_config.dart';
import 'audit_service.dart';
import '../risk/risk_rules.dart';
import 'backend.dart';

/// A user an admin should look at.
class FlaggedUser {
  final String uid;
  final String name;
  final String phone;
  final String riskTier;
  final int cancelCount;
  final int openReports;

  /// Behaviour counts used by the score (F7): loads in the last 24 hours and
  /// risk signals of the last 30 days.
  final int loadsLast24h;
  final int phoneChanges30d;
  final int manyDeviceSignals30d;
  final int gpsMismatches30d;

  /// Behavioural score and what contributed (see [RiskRules.score]).
  ({int score, List<String> reasons}) get assessment => RiskRules.score(
        cancelCount: cancelCount,
        openReports: openReports,
        tier: riskTier,
        loadsLast24h: loadsLast24h,
        phoneChanges30d: phoneChanges30d,
        manyDeviceSignals30d: manyDeviceSignals30d,
        gpsMismatches30d: gpsMismatches30d,
      );

  const FlaggedUser({
    required this.uid,
    required this.name,
    required this.phone,
    required this.riskTier,
    required this.cancelCount,
    required this.openReports,
    this.loadsLast24h = 0,
    this.phoneChanges30d = 0,
    this.manyDeviceSignals30d = 0,
    this.gpsMismatches30d = 0,
  });
}

class RiskService {
  RiskService._();

  static CollectionReference<Map<String, dynamic>> get _users => Backend.db.collection('users');

  /// Throws [AccountRestrictedException] when the signed-in user may not
  /// post, offer or accept. Firestore rules enforce the same.
  static Future<void> ensureCanTransact() async {
    final uid = Backend.requireUid();
    final tier = (await _users.doc(uid).get()).data()?['riskTier'] as String?;
    if (!RiskTier.canTransact(tier)) throw AccountRestrictedException(tier!);
  }

  /// Adds the +1 cancellation counter write to [tx] (the rules require it).
  static void countCancel(Transaction tx) =>
      tx.set(_users.doc(Backend.requireUid()), {'cancelCount': FieldValue.increment(1)}, SetOptions(merge: true));

  /// Admin only (rules).
  static Future<void> setTier(String uid, String tier, {String reason = ''}) async {
    if (!RiskTier.all.contains(tier)) throw ArgumentError.value(tier, 'tier');
    final batch = Backend.db.batch();
    batch.update(_users.doc(uid), {
      'riskTier': tier,
      'riskReason': reason.trim(),
      'riskUpdatedAt': FieldValue.serverTimestamp(),
    });
    AuditService.inBatch(batch, AuditType.riskChange, targetId: uid, data: {'tier': tier, 'reason': reason.trim()});
    await batch.commit();
  }

  /// Users with a non-normal tier, many cancellations or open reports, or a
  /// behaviour score at the review level (bursts of loads, phone changes,
  /// many devices, GPS far from the booked city). Thresholds: `config/risk`.
  static Future<List<FlaggedUser>> flagged({DateTime? now}) async {
    final cfg = RiskConfigStore.current;
    final t = now ?? DateTime.now();
    final results = await Future.wait([
      _users.where('riskTier', whereIn: [RiskTier.review, RiskTier.restricted, RiskTier.suspended, RiskTier.banned]).get(),
      _users.where('cancelCount', isGreaterThanOrEqualTo: cfg.cancelFlag).get(),
      Backend.db.collection('reports').where('status', isEqualTo: 'open').get(),
      Backend.db.collection('risk_signals').where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(t.subtract(const Duration(days: 30)))).get(),
      Backend.db.collection('loads').where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(t.subtract(const Duration(hours: 24)))).get(),
    ]);
    final reports = <String, int>{};
    for (final r in results[2].docs) {
      final id = r.data()['reportedId'] as String?;
      if (id != null) reports[id] = (reports[id] ?? 0) + 1;
    }
    final signals = <String, Map<String, int>>{};
    for (final d in results[3].docs) {
      final uid = d.data()['uid'] as String?;
      final type = d.data()['type'] as String?;
      if (uid != null && type != null) signals.putIfAbsent(uid, () => {}).update(type, (v) => v + 1, ifAbsent: () => 1);
    }
    final loads = <String, int>{};
    for (final d in results[4].docs) {
      final id = d.data()['shipperId'] as String?;
      if (id != null) loads[id] = (loads[id] ?? 0) + 1;
    }
    final users = <String, Map<String, dynamic>>{
      for (final d in [...results[0].docs, ...results[1].docs]) d.id: d.data(),
    };
    // Users only the behaviour counts point at.
    for (final id in {...reports.keys, ...signals.keys, ...loads.keys}) {
      if (!users.containsKey(id) && (reports.containsKey(id) || _behaviourScore(cfg, loads[id] ?? 0, signals[id] ?? const {}) >= cfg.reviewScore)) {
        users[id] = (await _users.doc(id).get()).data() ?? const {};
      }
    }
    final list = [
      for (final e in users.entries)
        FlaggedUser(
          uid: e.key,
          name: (e.value['name'] ?? e.value['driverName'] ?? '') as String,
          phone: e.value['phone'] as String? ?? '',
          riskTier: e.value['riskTier'] as String? ?? RiskTier.normal,
          cancelCount: (e.value['cancelCount'] as num?)?.toInt() ?? 0,
          openReports: reports[e.key] ?? 0,
          loadsLast24h: loads[e.key] ?? 0,
          phoneChanges30d: signals[e.key]?['phone_change'] ?? 0,
          manyDeviceSignals30d: signals[e.key]?['many_devices'] ?? 0,
          gpsMismatches30d: signals[e.key]?['gps_mismatch'] ?? 0,
        ),
    ];
    int weight(FlaggedUser u) => u.assessment.score * 1000 + RiskTier.all.indexOf(u.riskTier) * 100 + u.openReports * 10 + u.cancelCount;
    list.sort((a, b) => weight(b).compareTo(weight(a)));
    return list;
  }

  static int _behaviourScore(RiskConfig cfg, int loads, Map<String, int> signals) => RiskRules.score(
        cancelCount: 0,
        openReports: 0,
        loadsLast24h: loads,
        phoneChanges30d: signals['phone_change'] ?? 0,
        manyDeviceSignals30d: signals['many_devices'] ?? 0,
        gpsMismatches30d: signals['gps_mismatch'] ?? 0,
        config: cfg,
      ).score;

  /// F14 (free part): puts [uids] on `restricted` in one batch with an audit
  /// event each; users already restricted or worse are skipped. Admin only
  /// (rules). Returns how many were held. TODO(functions): do this
  /// automatically from a trigger instead of by an admin's tap.
  static Future<int> bulkHold(Iterable<FlaggedUser> users, {String reason = ''}) async {
    final targets = [for (final u in users) if (u.riskTier == RiskTier.normal || u.riskTier == RiskTier.review) u.uid];
    final text = reason.trim().isEmpty ? 'bulk hold' : reason.trim();
    var held = 0;
    for (var i = 0; i < targets.length; i += 200) {
      final batch = Backend.db.batch();
      for (final uid in targets.skip(i).take(200)) {
        batch.update(_users.doc(uid), {'riskTier': RiskTier.restricted, 'riskReason': text, 'riskUpdatedAt': FieldValue.serverTimestamp()});
        AuditService.inBatch(batch, AuditType.riskChange, targetId: uid, data: {'tier': RiskTier.restricted, 'reason': text, 'bulk': true});
        held++;
      }
      await batch.commit();
    }
    return held;
  }

  /// F1: accounts that share a device with [uid] or have the same name.
  static Future<List<DuplicateCandidate>> duplicatesOf(String uid) async {
    final db = Backend.db;
    final me = (await _users.doc(uid).get()).data() ?? const <String, dynamic>{};
    final devicesByUid = <String, Set<String>>{};
    final mine = await db.collection('device_links').where('uid', isEqualTo: uid).get();
    final deviceIds = {for (final d in mine.docs) d.data()['deviceId'] as String? ?? ''}..remove('');
    devicesByUid[uid] = deviceIds;
    for (final id in deviceIds) {
      final on = await db.collection('device_links').where('deviceId', isEqualTo: id).get();
      for (final d in on.docs) {
        final other = d.data()['uid'] as String?;
        if (other != null && other != uid) devicesByUid.putIfAbsent(other, () => {}).add(id);
      }
    }
    final key = RiskRules.nameKey((me['name'] ?? me['driverName'] ?? '') as String);
    final sameName = <String>{};
    if (key.length >= 4) {
      for (final field in ['name', 'driverName']) {
        final value = me[field] as String?;
        if (value == null || value.trim().isEmpty) continue;
        final found = await _users.where(field, isEqualTo: value).limit(20).get();
        for (final d in found.docs) {
          final n = (d.data()['name'] ?? d.data()['driverName'] ?? '') as String;
          if (d.id != uid && RiskRules.nameKey(n) == key) sameName.add(d.id);
        }
      }
    }
    return RiskRules.duplicates(uid, devicesByUid, sameName);
  }

  /// F3: anomalies on the vehicles of [uid] (admin view).
  static Future<List<({Vehicle vehicle, List<String> reasons})>> vehicleChecks(String uid) async {
    final snap = await Backend.db.collection('vehicles').where('ownerId', isEqualTo: uid).get();
    final vehicles = [for (final d in snap.docs) Vehicle.fromDoc(d)];
    final out = [for (final v in vehicles) (vehicle: v, reasons: RiskRules.vehicleAnomalies(v))];
    return [
      for (final e in out)
        if (e.reasons.isNotEmpty) e,
    ];
  }

  /// F3: an individual driver with more vehicles than [RiskRules.maxVehiclesPerDriver].
  static Future<bool> tooManyVehicles(String uid) async {
    final user = (await _users.doc(uid).get()).data();
    if (user?['role'] == 'fleet') return false;
    final snap = await Backend.db.collection('vehicles').where('ownerId', isEqualTo: uid).get();
    return snap.docs.length > RiskRules.maxVehiclesPerDriver;
  }
}
