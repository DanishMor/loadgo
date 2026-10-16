import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/ledger_entry.dart';
import '../models/payout.dart';
import '../money/money.dart';
import 'audit_service.dart';
import 'backend.dart';
import 'payout_service.dart';
import 'server_actions.dart';

/// The reason a finance action was refused before it was sent.
class FinanceException implements Exception {
  /// A translation key: `finNeedRef`, `finNeedReason`, `finNeedAmount` or `finSameAdmin`.
  final String key;
  const FinanceException(this.key);
}

/// Money actions of finance and super admins (F12). Every action is one batch:
/// the change plus an audit line (`payout_decision`, `wallet_freeze`,
/// `wallet_adjust`). Nothing is edited or deleted: a payout only moves forward
/// (requested, approved, paid) or closes (rejected, reversed), and a mistake
/// in the ledger is answered with a signed correction line. The rules enforce
/// the same (maker-checker, reasons, who may act).
class FinanceService {
  FinanceService._();

  static CollectionReference<Map<String, dynamic>> get _payouts => Backend.db.collection('payouts');

  static Stream<List<Payout>> watchPayouts() => PayoutService.watchAll();

  /// Ledger lines of everyone (newest 2000), for the daily check.
  static Stream<List<LedgerEntry>> watchLedger() => Backend.db.collection('ledger').limit(2000).snapshots().map((s) => [for (final d in s.docs) LedgerEntry.fromDoc(d)]);

  /// The server summaries (`wallets/{uid}`): person -> available + held + paid out. Empty until the server writes them.
  static Stream<Map<String, int>> watchSummaries() => Backend.db.collection('wallets').limit(2000).snapshots().map((s) {
        final out = <String, int>{};
        for (final d in s.docs) {
          final x = d.data();
          if (x['availablePaise'] is! num && x['heldPaise'] is! num && x['paidOutPaise'] is! num) continue;
          out[d.id] = (Money.parse(x['availablePaise']) + Money.parse(x['heldPaise']) + Money.parse(x['paidOutPaise'])).paise;
        }
        return out;
      });

  /// People whose payout details changed lately: person -> when.
  static Stream<Map<String, DateTime>> watchDetailsChanged({DateTime? since}) {
    final from = since ?? DateTime.now().subtract(const Duration(days: 30));
    return Backend.db.collection('users').where('payoutChangedAt', isGreaterThan: Timestamp.fromDate(from)).limit(500).snapshots().map((s) {
      final out = <String, DateTime>{};
      for (final d in s.docs) {
        final t = d.data()['payoutChangedAt'];
        if (t is Timestamp) out[d.id] = t.toDate();
      }
      return out;
    });
  }

  static Stream<bool> watchFrozen(String uid) => Backend.db.collection('wallet_freezes').doc(uid).snapshots().map((s) => s.data()?['frozen'] == true);

  static String _text(String v) => v.trim();

  static void _needReason(String reason, {int min = 3}) {
    final r = _text(reason);
    if (r.length < min || r.length > 200) throw const FinanceException('finNeedReason');
  }

  static Future<void> _payoutStep(Payout p, Map<String, Object?> changes, String action) {
    final batch = Backend.db.batch();
    batch.update(_payouts.doc(p.id), changes);
    AuditService.inBatch(batch, AuditType.payoutDecision, targetId: p.id, data: {'action': action, 'amountPaise': p.amountPaise});
    return batch.commit();
  }

  /// Maker: approve a request.
  static Future<void> approve(Payout p) async {
    final me = Backend.requireUid();
    // With the serverWallet switch on and the function deployed, the server does it (same rules, same audit line).
    if (await ServerActions.payoutDecision(p.id, 'approve')) return;
    await _payoutStep(p, {'status': Payout.approved, 'approvedBy': me, 'approvedAt': FieldValue.serverTimestamp()}, 'approve');
  }

  /// Checker: mark an approved payout paid, with the bank or UPI reference. A different person from the approver.
  static Future<void> pay(Payout p, String reference) async {
    final me = Backend.requireUid();
    if (p.approvedBy == me) throw const FinanceException('finSameAdmin');
    final ref = _text(reference);
    if (ref.length < 4 || ref.length > 60) throw const FinanceException('finNeedRef');
    if (await ServerActions.payoutDecision(p.id, 'pay', reference: ref)) return;
    await _payoutStep(p, {'status': Payout.paid, 'paidBy': me, 'paidAt': FieldValue.serverTimestamp(), 'reference': ref}, 'pay');
  }

  static Future<void> reject(Payout p, String reason) async {
    _needReason(reason);
    final me = Backend.requireUid();
    if (await ServerActions.payoutDecision(p.id, 'reject', reason: _text(reason))) return;
    await _payoutStep(p, {'status': Payout.rejected, 'handledBy': me, 'handledAt': FieldValue.serverTimestamp(), 'reason': _text(reason)}, 'reject');
  }

  static Future<void> reverse(Payout p, String reason) async {
    _needReason(reason, min: 5);
    final me = Backend.requireUid();
    if (await ServerActions.payoutDecision(p.id, 'reverse', reason: _text(reason))) return;
    await _payoutStep(p, {'status': Payout.reversed, 'reversedBy': me, 'reversedAt': FieldValue.serverTimestamp(), 'reason': _text(reason)}, 'reverse');
  }

  /// Stops (or allows again) payouts for one person, with a reason.
  static Future<void> setFrozen(String uid, bool frozen, String reason) async {
    _needReason(reason);
    final id = _text(uid);
    if (id.isEmpty || id.length > 60) throw const FinanceException('finNeedUser');
    final batch = Backend.db.batch();
    batch.set(Backend.db.collection('wallet_freezes').doc(id), {
      'frozen': frozen,
      'reason': _text(reason),
      'by': Backend.requireUid(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    AuditService.inBatch(batch, AuditType.walletFreeze, targetId: id, data: {'action': frozen ? 'freeze' : 'unfreeze'});
    await batch.commit();
  }

  /// A signed correction line (positive adds, negative takes back). Whole paise within +-Rs 100 crore.
  static Future<void> adjust(String driverId, int amountPaise, String reason) async {
    _needReason(reason, min: 5);
    final id = _text(driverId);
    if (id.isEmpty || id.length > 60) throw const FinanceException('finNeedUser');
    if (amountPaise == 0 || amountPaise.abs() > 100000000000) throw const FinanceException('finNeedAmount');
    final batch = Backend.db.batch();
    final line = Backend.db.collection('ledger').doc('adj_${_randomId()}');
    batch.set(line, {
      'driverId': id,
      'type': LedgerType.adjustment,
      'amountPaise': amountPaise,
      'reason': _text(reason),
      'by': Backend.requireUid(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    AuditService.inBatch(batch, AuditType.walletAdjust, targetId: id, data: {'action': 'adjust', 'amountPaise': amountPaise});
    await batch.commit();
  }

  static final _random = Random.secure();

  /// 16 random letters and digits: a correction id nobody can guess or collide with.
  static String _randomId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return String.fromCharCodes([for (var i = 0; i < 16; i++) chars.codeUnitAt(_random.nextInt(chars.length))]);
  }
}
