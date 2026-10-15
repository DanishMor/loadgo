import '../../models/ledger_entry.dart';
import '../../models/payout.dart';
import '../../money/money.dart';
import '../../money/wallet_book.dart';
import '../../admin/admin_export.dart';
import '../../payments/earnings_statement.dart' show EarningsStatement;

/// What the finance team sees (F12). All pure: the screens feed it the stored
/// payouts, ledger lines and server summaries.

/// The stage a payout is in, for the queue tabs.
enum PayoutStage { waitingApproval, waitingPayment, done, closed }

PayoutStage stageOf(Payout p) => switch (p.status) {
      Payout.requested => PayoutStage.waitingApproval,
      Payout.approved => PayoutStage.waitingPayment,
      Payout.paid => PayoutStage.done,
      _ => PayoutStage.closed, // rejected, reversed
    };

/// Who may do what to a payout (the rules enforce the same; this hides buttons).
class PayoutActions {
  PayoutActions._();

  /// The maker approves a request.
  static bool canApprove(Payout p) => p.status == Payout.requested;

  /// The checker pays an approved one, and must be a different person from the maker.
  static bool canPay(Payout p, String? me) => p.status == Payout.approved && me != null && p.approvedBy != null && p.approvedBy != me;

  /// Rejecting works before payment.
  static bool canReject(Payout p) => p.isOpen;

  /// A paid payout that came back.
  static bool canReverse(Payout p) => p.status == Payout.paid;

  /// Why [canPay] is false for an approved payout, as a translation key (or null).
  static String? whyNotPay(Payout p, String? me) {
    if (p.status != Payout.approved) return null;
    if (me != null && p.approvedBy == me) return 'finSameAdmin';
    return null;
  }
}

enum AnomalyKind { bigPayout, newAccountBig, manyInOneDay }

class Anomaly {
  final String payoutId;
  final String driverId;
  final AnomalyKind kind;
  const Anomaly(this.payoutId, this.driverId, this.kind);
}

/// Checks that make a person look twice (they never block anything by themselves).
class AnomalyRules {
  AnomalyRules._();

  /// A single payout at or above this is "big" (Rs 50,000).
  static const bigPaise = 5000000;

  /// A payout above [newAccountBigPaise] within this many days of a change of
  /// payout details is flagged.
  static const newAccountDays = 7;
  static const newAccountBigPaise = 1000000; // Rs 10,000

  /// This many payouts requested by one person in one (local) day.
  static const perDay = 3;

  static List<Anomaly> detect(Iterable<Payout> payouts, {Map<String, DateTime> detailsChangedAt = const {}, required DateTime now}) {
    final out = <Anomaly>[];
    final perDriverDay = <String, List<Payout>>{};
    for (final p in payouts) {
      if (p.status == Payout.rejected) continue;
      if (p.amountPaise >= bigPaise) out.add(Anomaly(p.id, p.driverId, AnomalyKind.bigPayout));
      final changed = detailsChangedAt[p.driverId];
      if (changed != null && p.amountPaise >= newAccountBigPaise && now.difference(changed).inDays < newAccountDays && !changed.isAfter(now)) {
        out.add(Anomaly(p.id, p.driverId, AnomalyKind.newAccountBig));
      }
      final at = p.createdAt;
      if (at != null) perDriverDay.putIfAbsent('${p.driverId}|${at.year}-${at.month}-${at.day}', () => []).add(p);
    }
    for (final list in perDriverDay.values) {
      if (list.length >= perDay) {
        for (final p in list) {
          out.add(Anomaly(p.id, p.driverId, AnomalyKind.manyInOneDay));
        }
      }
    }
    return out;
  }
}

/// One person's row in the daily reconciliation.
class ReconRow {
  final String driverId;

  /// Earnings, commission and corrections in the ledger.
  final int ledgerNetPaise;

  /// The four boxes worked out from ledger + payouts.
  final WalletBalance balance;

  /// What the server summary says (null: no summary written).
  final int? summaryTotalPaise;

  const ReconRow(this.driverId, this.ledgerNetPaise, this.balance, this.summaryTotalPaise);

  /// The boxes add up to the ledger.
  bool get balanced => balance.lifetime.paise == ledgerNetPaise;

  /// More has been asked for or paid than was earned.
  bool get overdrawn => !balance.isSound;

  /// The server summary and the lines disagree.
  bool get summaryMismatch => summaryTotalPaise != null && summaryTotalPaise != balance.lifetime.paise;

  bool get ok => balanced && !overdrawn && !summaryMismatch;
}

class Reconciliation {
  final List<ReconRow> rows;
  const Reconciliation(this.rows);

  /// Rows that need a look, worst first.
  List<ReconRow> get problems => [for (final r in rows) if (!r.ok) r]..sort((a, b) => b.balance.lifetime.paise.abs().compareTo(a.balance.lifetime.paise.abs()));

  /// What Load 20 owes people today: available + held (not yet paid out).
  int get owedPaise => rows.fold(0, (a, r) => a + r.balance.available.atLeastZero.paise + r.balance.held.atLeastZero.paise);

  int get paidOutPaise => rows.fold(0, (a, r) => a + r.balance.paidOut.atLeastZero.paise);

  /// [summaries] maps a person to the total the server summary holds (available + held + paid out).
  static Reconciliation run({required Iterable<LedgerEntry> ledger, required Iterable<Payout> payouts, Map<String, int> summaries = const {}}) {
    final byLedger = <String, List<LedgerEntry>>{};
    for (final l in ledger) {
      if (l.driverId.isEmpty) continue;
      byLedger.putIfAbsent(l.driverId, () => []).add(l);
    }
    final byPayout = <String, List<Payout>>{};
    for (final p in payouts) {
      if (p.driverId.isEmpty) continue;
      byPayout.putIfAbsent(p.driverId, () => []).add(p);
    }
    final ids = {...byLedger.keys, ...byPayout.keys};
    final rows = <ReconRow>[];
    for (final id in ids) {
      final lines = byLedger[id] ?? const <LedgerEntry>[];
      final book = WalletBook.fromSources(ledger: lines, payouts: byPayout[id] ?? const <Payout>[]);
      var net = Money.zero;
      for (final l in lines) {
        if (l.type == LedgerType.tripEarning || l.type == LedgerType.platformCommission || l.type == LedgerType.adjustment) {
          net = net + Money(l.amountPaise).clamped;
        }
      }
      rows.add(ReconRow(id, net.paise, book.balance, summaries[id]));
    }
    rows.sort((a, b) => a.driverId.compareTo(b.driverId));
    return Reconciliation(rows);
  }

  static const csvHeader = 'driver,ledger_net_inr,available_inr,held_inr,paid_out_inr,summary_inr,status';

  String toCsv() {
    final lines = [csvHeader];
    String r(int p) => EarningsStatement.rupees(p);
    for (final x in rows) {
      final status = x.ok ? 'ok' : [if (!x.balanced) 'not_balanced', if (x.overdrawn) 'overdrawn', if (x.summaryMismatch) 'summary_mismatch'].join('+');
      lines.add([x.driverId, r(x.ledgerNetPaise), r(x.balance.available.paise), r(x.balance.held.paise), r(x.balance.paidOut.paise), x.summaryTotalPaise == null ? '' : r(x.summaryTotalPaise!), status].map(AdminExport.cell).join(','));
    }
    return '${lines.join('\n')}\n';
  }
}

/// The payout queue as a CSV for finance (driver ids, amounts, status, who approved and paid).
String payoutQueueCsv(Iterable<Payout> payouts) {
  const header = 'payout,driver,amount_inr,status,approved_by,paid_by,reference,requested';
  String r(int p) => EarningsStatement.rupees(p);
  String day(DateTime? d) => d == null ? '' : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  final lines = [header];
  for (final p in payouts) {
    lines.add([p.id, p.driverId, r(p.amountPaise), p.status, p.approvedBy ?? '', p.paidBy ?? '', p.reference ?? '', day(p.createdAt)].map(AdminExport.cell).join(','));
  }
  return '${lines.join('\n')}\n';
}
