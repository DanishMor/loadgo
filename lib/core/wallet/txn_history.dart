import '../constants/logistics.dart';
import '../models/booking.dart';
import '../models/driver_extras.dart';
import '../models/earnings.dart';
import '../models/ledger_entry.dart';
import '../models/payout.dart';
import '../offers/promo.dart';

class TxnKind {
  TxnKind._();
  static const trip = 'trip'; // customer paid for a trip
  static const earning = 'earning';
  static const commission = 'commission';
  static const payout = 'payout';
  static const tip = 'tip';
  static const credit = 'credit';
  static const all = [trip, earning, commission, payout, tip, credit];
}

/// One line of the history, from the signed-in user's point of view: positive
/// is money in, negative is money out (paise). Records only.
class TxnLine {
  final String id;
  final DateTime date;
  final String kind;
  final int amountPaise;
  final String bookingId;

  /// 'pending' for amounts that are not settled yet (unpaid trip, payout asked).
  final bool pending;

  const TxnLine({required this.id, required this.date, required this.kind, required this.amountPaise, this.bookingId = '', this.pending = false});

  bool get isIn => amountPaise >= 0;
}

enum TxnDirection { all, moneyIn, moneyOut }

class TxnFilter {
  final Set<String> kinds; // empty = every kind
  final TxnDirection direction;
  final DateTime? from;

  const TxnFilter({this.kinds = const {}, this.direction = TxnDirection.all, this.from});

  bool matches(TxnLine l) {
    if (kinds.isNotEmpty && !kinds.contains(l.kind)) return false;
    if (from != null && l.date.isBefore(from!)) return false;
    return switch (direction) {
      TxnDirection.all => true,
      TxnDirection.moneyIn => l.isIn,
      TxnDirection.moneyOut => !l.isIn,
    };
  }
}

class TxnSummary {
  final int moneyIn;
  final int moneyOut;
  const TxnSummary(this.moneyIn, this.moneyOut);
  int get net => moneyIn + moneyOut;
}

class TxnHistory {
  TxnHistory._();

  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  /// Driver: wallet ledger, payouts (asked = pending, paid = settled, rejected skipped) and tips received.
  static List<TxnLine> forDriver({
    required Iterable<LedgerEntry> ledger,
    required Iterable<Payout> payouts,
    required Iterable<Tip> tips,
  }) =>
      _sorted([
        for (final e in ledger)
          TxnLine(
            id: 'l_${e.id}',
            date: e.createdAt ?? _epoch,
            kind: e.type == LedgerType.platformCommission ? TxnKind.commission : TxnKind.earning,
            amountPaise: e.amountPaise,
            bookingId: e.bookingId,
          ),
        for (final p in payouts)
          if (p.status != Payout.rejected)
            TxnLine(id: 'p_${p.id}', date: p.createdAt ?? _epoch, kind: TxnKind.payout, amountPaise: -p.amountPaise, pending: p.status == Payout.requested),
        for (final t in tips)
          TxnLine(id: 't_${t.bookingId}', date: t.createdAt ?? _epoch, kind: TxnKind.tip, amountPaise: t.amountPaise, bookingId: t.bookingId),
      ]);

  /// Customer: delivered trips (pending until the driver confirmed payment), tips given and credit lines.
  static List<TxnLine> forCustomer({
    required Iterable<Booking> bookings,
    required Iterable<Tip> tips,
    required Iterable<CreditLine> credits,
  }) =>
      _sorted([
        for (final b in bookings)
          if (b.status == BookingStatus.delivered && (b.billAmountPaise ?? 0) > 0)
            TxnLine(
              id: 'b_${b.id}',
              date: EarningsSummary.deliveredAt(b),
              kind: TxnKind.trip,
              amountPaise: -b.billAmountPaise!,
              bookingId: b.id,
              pending: b.paymentStatus != PaymentStatus.driverConfirmed,
            ),
        for (final t in tips)
          TxnLine(id: 't_${t.bookingId}', date: t.createdAt ?? _epoch, kind: TxnKind.tip, amountPaise: -t.amountPaise, bookingId: t.bookingId),
        for (final c in credits)
          TxnLine(id: 'c_${c.id}', date: c.createdAt ?? _epoch, kind: TxnKind.credit, amountPaise: c.amountPaise, bookingId: c.loadId ?? ''),
      ]);

  static List<TxnLine> _sorted(List<TxnLine> l) => l..sort((a, b) => b.date.compareTo(a.date));

  static List<TxnLine> apply(Iterable<TxnLine> lines, TxnFilter f) => [for (final l in lines) if (f.matches(l)) l];

  /// Settled lines only: pending amounts are not counted yet.
  static TxnSummary summary(Iterable<TxnLine> lines) {
    var i = 0, o = 0;
    for (final l in lines) {
      if (l.pending) continue;
      if (l.isIn) {
        i += l.amountPaise;
      } else {
        o += l.amountPaise;
      }
    }
    return TxnSummary(i, o);
  }

  static String _rupees(int paise) => '${paise < 0 ? '-' : ''}${paise.abs() ~/ 100}.${(paise.abs() % 100).toString().padLeft(2, '0')}';

  /// `date,type,booking,status,amount_rupees` (amount signed: money out is negative).
  static String toCsv(Iterable<TxnLine> lines) {
    final rows = ['date,type,booking,status,amount_rupees'];
    for (final l in lines) {
      final d = l.date;
      final date = d == _epoch ? '' : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      rows.add('$date,${l.kind},${l.bookingId},${l.pending ? 'pending' : 'settled'},${_rupees(l.amountPaise)}');
    }
    return rows.join('\n');
  }
}
