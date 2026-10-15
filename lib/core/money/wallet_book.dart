import '../models/ledger_entry.dart';
import 'money.dart';

/// The kinds of line in a person's earnings book (F7). Each line moves money
/// between at most two of the four boxes: pending, available, held (asked for
/// payout), paid out. The balance is ONLY the sum of the lines, never a stored
/// number that could drift.
class WalletKind {
  WalletKind._();

  /// Delivered, customer has not confirmed payment yet: pending +amount.
  static const pendingEarning = 'pending_earning';

  /// Pending turns into money you can ask for: pending -amount.
  static const pendingSettle = 'pending_settle';

  /// A confirmed trip earning: available +amount.
  static const tripEarning = LedgerType.tripEarning;

  /// LoadGo's commission, stored negative: available +amount (amount < 0).
  static const commission = LedgerType.platformCommission;

  /// Payout asked: available -amount, held +amount (amount > 0).
  static const payoutHold = 'payout_hold';

  /// Payout rejected or cancelled before payment: held -amount, available +amount.
  static const payoutRelease = 'payout_release';

  /// Payout paid: held -amount, paid out +amount.
  static const payoutPaid = 'payout_paid';

  /// A paid payout that came back (failed transfer): paid out -amount, available +amount.
  static const payoutReversal = 'payout_reversal';

  /// A correction by an admin, with a reason (signed): available +amount.
  static const adjustment = 'adjustment';

  static const all = [
    pendingEarning,
    pendingSettle,
    tripEarning,
    commission,
    payoutHold,
    payoutRelease,
    payoutPaid,
    payoutReversal,
    adjustment,
  ];

  /// Kinds whose amount must be above zero (the sign is in the kind).
  static const positiveOnly = [pendingEarning, pendingSettle, payoutHold, payoutRelease, payoutPaid, payoutReversal];
}

/// One line. [key] is the idempotency key: the same key is applied once, so a
/// retry, a replay or a double tap cannot count twice.
class WalletEntry {
  final String key;
  final String kind;
  final Money amount;
  final DateTime? at;

  const WalletEntry({required this.key, required this.kind, required this.amount, this.at});

  /// Largest single line (Rs 100 crore).
  static const maxPaise = 100000000000;

  /// The existing `ledger/{bookingId}_{type}` document, whose id already is the key.
  factory WalletEntry.fromLedger(LedgerEntry e) =>
      WalletEntry(key: e.id, kind: e.type, amount: Money(e.amountPaise).clamped, at: e.createdAt);

  /// null when the line is usable, otherwise why not.
  String? get problem {
    if (key.isEmpty || key.length > 200) return 'key';
    if (!WalletKind.all.contains(kind)) return 'kind';
    final p = amount.paise;
    if (p == 0) return 'zero';
    if (p.abs() > maxPaise) return 'too_big';
    if (kind == WalletKind.commission && p > 0) return 'commission_sign';
    if (WalletKind.positiveOnly.contains(kind) && p < 0) return 'negative';
    return null;
  }
}

/// The four boxes.
class WalletBalance {
  final Money pending;
  final Money available;
  final Money held;
  final Money paidOut;

  const WalletBalance({this.pending = Money.zero, this.available = Money.zero, this.held = Money.zero, this.paidOut = Money.zero});

  /// What the person has earned in total and not had to give back:
  /// available + held + paid out.
  Money get lifetime => available + held + paidOut;

  /// No box is below zero.
  bool get isSound => !pending.isNegative && !available.isNegative && !held.isNegative && !paidOut.isNegative;

  @override
  bool operator ==(Object other) => other is WalletBalance && other.pending == pending && other.available == available && other.held == held && other.paidOut == paidOut;

  @override
  int get hashCode => Object.hash(pending.paise, available.paise, held.paise, paidOut.paise);

  @override
  String toString() => 'pending ${pending.debug}, available ${available.debug}, held ${held.debug}, paid out ${paidOut.debug}';
}

/// What happened when a line was offered to a [WalletBook].
enum AppendResult { applied, duplicate, invalid, wouldGoNegative }

/// A list of lines with the rules around them. Pure Dart, no Firestore.
class WalletBook {
  final List<WalletEntry> _entries = [];
  final Set<String> _keys = {};
  Money _pending = Money.zero, _available = Money.zero, _held = Money.zero, _paid = Money.zero;

  WalletBook();

  /// Rebuilds from stored lines. Duplicate keys and unusable lines are skipped
  /// (the first of a key wins). Old data that would have gone below zero is
  /// kept as it is and shown with [WalletBalance.isSound] false, so a bad
  /// legacy document never hides money or crashes a screen.
  factory WalletBook.of(Iterable<WalletEntry> entries) {
    final b = WalletBook();
    for (final e in entries) {
      b._apply(e, force: true);
    }
    return b;
  }

  List<WalletEntry> get entries => List.unmodifiable(_entries);

  WalletBalance get balance => WalletBalance(pending: _pending, available: _available, held: _held, paidOut: _paid);

  /// What the four boxes must add up to, worked out from the lines alone:
  /// pending earnings - settled + trip earnings + commission + adjustments.
  /// Payout lines only move money between boxes, so they are not in it.
  /// A correct book always has `balance` boxes adding up to this.
  Money get netInflow {
    var t = Money.zero;
    for (final e in _entries) {
      switch (e.kind) {
        case WalletKind.pendingEarning:
        case WalletKind.tripEarning:
        case WalletKind.commission:
        case WalletKind.adjustment:
          t = t + e.amount;
        case WalletKind.pendingSettle:
          t = t - e.amount;
        default:
          break;
      }
    }
    return t;
  }

  /// pending + available + held + paid out.
  Money get boxTotal => _pending + _available + _held + _paid;

  /// Offers a new line (a payout request, an admin correction...). Nothing
  /// changes unless the result is [AppendResult.applied].
  AppendResult tryAppend(WalletEntry e) {
    if (e.problem != null) return AppendResult.invalid;
    if (_keys.contains(e.key)) return AppendResult.duplicate;
    return _apply(e, force: false);
  }

  AppendResult _apply(WalletEntry e, {required bool force}) {
    if (e.problem != null) return AppendResult.invalid;
    if (_keys.contains(e.key)) return AppendResult.duplicate;
    final a = e.amount;
    var p = _pending, v = _available, h = _held, o = _paid;
    switch (e.kind) {
      case WalletKind.pendingEarning:
        p = p + a;
      case WalletKind.pendingSettle:
        p = p - a;
      case WalletKind.tripEarning:
      case WalletKind.commission:
      case WalletKind.adjustment:
        v = v + a;
      case WalletKind.payoutHold:
        v = v - a;
        h = h + a;
      case WalletKind.payoutRelease:
        h = h - a;
        v = v + a;
      case WalletKind.payoutPaid:
        h = h - a;
        o = o + a;
      case WalletKind.payoutReversal:
        o = o - a;
        v = v + a;
    }
    final sound = !p.isNegative && !v.isNegative && !h.isNegative && !o.isNegative;
    // New lines may not push any box below zero. Stored lines are taken as they are.
    if (!force && !sound) return AppendResult.wouldGoNegative;
    _pending = p;
    _available = v;
    _held = h;
    _paid = o;
    _entries.add(e);
    _keys.add(e.key);
    return AppendResult.applied;
  }
}
