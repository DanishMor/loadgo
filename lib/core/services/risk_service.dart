import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/risk.dart';
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

  /// Behavioural score and what contributed (see [RiskRules.score]).
  ({int score, List<String> reasons}) get assessment =>
      RiskRules.score(cancelCount: cancelCount, openReports: openReports, tier: riskTier);

  const FlaggedUser({
    required this.uid,
    required this.name,
    required this.phone,
    required this.riskTier,
    required this.cancelCount,
    required this.openReports,
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

  /// Users with a non-normal tier, many cancellations or open reports.
  static Future<List<FlaggedUser>> flagged() async {
    final results = await Future.wait([
      _users.where('riskTier', whereIn: [RiskTier.review, RiskTier.restricted, RiskTier.suspended, RiskTier.banned]).get(),
      _users.where('cancelCount', isGreaterThanOrEqualTo: cancelFlagThreshold).get(),
      Backend.db.collection('reports').where('status', isEqualTo: 'open').get(),
    ]);
    final reports = <String, int>{};
    for (final r in results[2].docs) {
      final id = r.data()['reportedId'] as String?;
      if (id != null) reports[id] = (reports[id] ?? 0) + 1;
    }
    final users = <String, Map<String, dynamic>>{
      for (final d in [...results[0].docs, ...results[1].docs]) d.id: d.data(),
    };
    for (final id in reports.keys) {
      if (!users.containsKey(id)) users[id] = (await _users.doc(id).get()).data() ?? const {};
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
        ),
    ];
    int weight(FlaggedUser u) => RiskTier.all.indexOf(u.riskTier) * 100 + u.openReports * 10 + u.cancelCount;
    list.sort((a, b) => weight(b).compareTo(weight(a)));
    return list;
  }
}
