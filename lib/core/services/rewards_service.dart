import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../offers/promo.dart';
import 'backend.dart';
import 'audit_service.dart';

enum ReferralProblem { unknownCode, ownCode, alreadyReferred, tooLate }

class ReferralException implements Exception {
  final ReferralProblem problem;
  const ReferralException(this.problem);

  @override
  String toString() => 'ReferralException($problem)';
}

/// Promo codes, the credits ledger and referrals (customer side), plus the
/// admin helpers. Everything here is a record: no money moves, and balances
/// are summed on the device. TODO(functions): server-side balance, expiry and
/// settlement; LATER(paid): paying out or topping up credits.
class RewardsService {
  RewardsService._();

  static const defaultReferralBonusPaise = 10000;
  static const _codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static FirebaseFirestore get _db => Backend.db;
  static CollectionReference<Map<String, dynamic>> get _promos => _db.collection('promos');

  static DocumentReference<Map<String, dynamic>> _user(String uid) => _db.collection('users').doc(uid);

  // ------------------------------------------------------------------
  // promo codes
  // ------------------------------------------------------------------

  static Future<Promo?> getPromo(String code) async {
    final id = Promo.normaliseCode(code);
    if (!Promo.validCode(id)) return null;
    final snap = await _promos.doc(id).get();
    return snap.exists ? Promo.fromMap(id, snap.data()!) : null;
  }

  /// Checks [code] for an order of [totalPaise] and picks the numbered
  /// documents it will occupy. Throws [PromoException]. Nothing is written
  /// until [addRedemption] is added to the load's batch.
  static Future<PromoApplication> reserve(String code, int totalPaise, {DateTime? now, Random? random}) async {
    final uid = Backend.requireUid();
    final promo = await getPromo(code);
    if (promo == null) throw const PromoException(PromoProblem.unknown);
    final problem = promo.problemFor(totalPaise, now ?? DateTime.now());
    if (problem == PromoProblem.belowMinimum) {
      throw PromoException(problem!, minOrderPaise: promo.minOrderPaise);
    }
    if (problem != null) throw PromoException(problem);
    final discount = promo.discountFor(totalPaise);
    if (discount <= 0) throw const PromoException(PromoProblem.belowMinimum);

    // The user's own use number: the first of uid_1..uid_perUserLimit that is free.
    int? use;
    for (var m = 1; m <= promo.perUserLimit; m++) {
      if (!(await _promos.doc(promo.code).collection('uses').doc('${uid}_$m').get()).exists) {
        use = m;
        break;
      }
    }
    if (use == null) throw const PromoException(PromoProblem.usedUp);

    // A free global slot: scan small limits, probe random numbers for big ones.
    final rnd = random ?? Random();
    final candidates = promo.usageLimit <= 25
        ? [for (var n = 1; n <= promo.usageLimit; n++) n]
        : <int>{for (var i = 0; i < 40; i++) 1 + rnd.nextInt(promo.usageLimit)}.toList();
    int? slot;
    for (final n in candidates) {
      if (!(await _promos.doc(promo.code).collection('slots').doc('$n').get()).exists) {
        slot = n;
        break;
      }
    }
    if (slot == null) throw const PromoException(PromoProblem.exhausted);
    return PromoApplication(promo: promo, discountPaise: discount, slot: slot, use: use);
  }

  /// The create-only slot and per-user documents for [app], tied to [loadId].
  static void addRedemption(WriteBatch batch, PromoApplication app, {required String loadId, required String uid}) {
    final base = _promos.doc(app.promo.code);
    final record = {'loadId': loadId, 'createdAt': FieldValue.serverTimestamp()};
    batch.set(base.collection('slots').doc('${app.slot}'), record);
    batch.set(base.collection('uses').doc('${uid}_${app.use}'), {'uid': uid, ...record});
  }

  // ------------------------------------------------------------------
  // credits
  // ------------------------------------------------------------------

  static Stream<List<CreditLine>> watchCredits() {
    final uid = Backend.uid;
    if (uid == null) return Stream.value(const []);
    return _user(uid).collection('credits').snapshots().map((s) {
      final list = [for (final d in s.docs) CreditLine.fromDoc(d.id, d.data())];
      list.sort((a, b) => (b.createdAt ?? DateTime.now()).compareTo(a.createdAt ?? DateTime.now()));
      return list;
    });
  }

  static Future<int> balance() async {
    final uid = Backend.requireUid();
    final s = await _user(uid).collection('credits').get();
    return CreditLine.balance([for (final d in s.docs) CreditLine.fromDoc(d.id, d.data())]);
  }

  /// Spend line for a new load (paid from credits), in the load's batch.
  static void addSpend(WriteBatch batch, {required String uid, required String loadId, required int paise}) {
    batch.set(_user(uid).collection('credits').doc('spend_$loadId'), {
      'amountPaise': -paise,
      'kind': 'spend',
      'loadId': loadId,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ------------------------------------------------------------------
  // referrals
  // ------------------------------------------------------------------

  /// Read fresh each time (not cached): the rules compare a referral credit
  /// with the bonus stored on the server, so a value kept for minutes after an
  /// admin changed it would make the credit write fail (MASTER-5 bug B-5-1).
  static Future<int> referralBonus() async {
    final d = (await _db.collection('config').doc('offers').get()).data();
    return (d?['referralBonusPaise'] as num?)?.toInt() ?? defaultReferralBonusPaise;
  }

  static String _randomCode(Random r) => String.fromCharCodes([for (var i = 0; i < 6; i++) _codeAlphabet.codeUnitAt(r.nextInt(_codeAlphabet.length))]);

  /// The signed-in user's own referral code, created on first use.
  static Future<String> ensureReferralCode({Random? random}) async {
    final uid = Backend.requireUid();
    final existing = (await _user(uid).get()).data()?['referralCode'] as String?;
    if (existing != null) return existing;
    final rnd = random ?? Random.secure();
    for (var i = 0; i < 6; i++) {
      final code = _randomCode(rnd);
      if ((await _db.collection('referral_codes').doc(code).get()).exists) continue;
      final batch = _db.batch();
      batch.set(_user(uid), {'referralCode': code}, SetOptions(merge: true));
      batch.set(_db.collection('referral_codes').doc(code), {'uid': uid, 'createdAt': FieldValue.serverTimestamp()});
      try {
        await batch.commit();
        return code;
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') rethrow; // lost a race for this code: try another
      }
    }
    throw StateError('Could not create a referral code');
  }

  static Future<bool> hasReferrer() async => (await _db.collection('referrals').doc(Backend.requireUid()).get()).exists;

  /// Apply a friend's code (once, in the first 7 days). Both sides get a
  /// credit line of the configured bonus. Throws [ReferralException].
  static Future<int> applyReferral(String code, {DateTime? now}) async {
    final uid = Backend.requireUid();
    final id = Promo.normaliseCode(code);
    final me = (await _user(uid).get()).data() ?? const {};
    if (id == me['referralCode']) throw const ReferralException(ReferralProblem.ownCode);
    if (await hasReferrer()) throw const ReferralException(ReferralProblem.alreadyReferred);
    final created = (me['createdAt'] as Timestamp?)?.toDate();
    if (created != null && (now ?? DateTime.now()).difference(created) > const Duration(days: 7)) {
      throw const ReferralException(ReferralProblem.tooLate);
    }
    final owner = (await _db.collection('referral_codes').doc(id).get()).data()?['uid'] as String?;
    if (owner == null) throw const ReferralException(ReferralProblem.unknownCode);
    if (owner == uid) throw const ReferralException(ReferralProblem.ownCode);

    final bonus = await referralBonus();
    final batch = _db.batch();
    batch.set(_db.collection('referrals').doc(uid), {'referrerUid': owner, 'code': id, 'createdAt': FieldValue.serverTimestamp()});
    Map<String, Object> line() => {'amountPaise': bonus, 'kind': 'referral', 'createdAt': FieldValue.serverTimestamp()};
    batch.set(_user(uid).collection('credits').doc('referral_in'), line());
    batch.set(_user(owner).collection('credits').doc('referral_from_$uid'), line());
    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') throw const ReferralException(ReferralProblem.tooLate);
      rethrow;
    }
    return bonus;
  }

  // ------------------------------------------------------------------
  // admin (rules let only admins write these)
  // ------------------------------------------------------------------

  static Stream<List<Promo>> watchPromos() => _promos.snapshots().map((s) {
        final list = [for (final d in s.docs) Promo.fromMap(d.id, d.data())];
        list.sort((a, b) => a.code.compareTo(b.code));
        return list;
      });

  static Future<void> savePromo(Promo p) async {
    final ref = _promos.doc(p.code);
    final isNew = !(await ref.get()).exists;
    final batch = _db.batch();
    batch.set(ref, {
      ...p.toMap(),
      if (isNew) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    AuditService.inBatch(batch, AuditType.userAction, targetId: p.code, data: {'action': isNew ? 'promo_create' : 'promo_update'});
    await batch.commit();
  }

  /// Positive = grant, negative = take back. A record only.
  static Future<void> grantCredits(String uid, int paise, {String note = ''}) {
    if (paise == 0) throw ArgumentError.value(paise, 'paise');
    final batch = _db.batch();
    batch.set(_user(uid).collection('credits').doc(), {
      'amountPaise': paise,
      'kind': paise > 0 ? 'admin_grant' : 'admin_deduct',
      if (note.trim().isNotEmpty) 'note': note.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    AuditService.inBatch(batch, AuditType.userAction, targetId: uid, data: {'action': 'credits', 'amountPaise': paise});
    return batch.commit();
  }

  static Future<void> setReferralBonus(int paise) {
    final batch = _db.batch();
    batch.set(_db.collection('config').doc('offers'), {'referralBonusPaise': paise}, SetOptions(merge: true));
    AuditService.inBatch(batch, AuditType.configChange, targetId: 'offers', data: {'doc': 'offers', 'changedKeys': ['referralBonusPaise']});
    return batch.commit();
  }
}
