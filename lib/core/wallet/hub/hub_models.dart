import '../../constants/logistics.dart';
import '../../models/booking.dart';
import '../../models/ledger_entry.dart';
import '../../models/payout.dart';
import '../../money/money.dart';
import '../../money/wallet_book.dart';
import '../../offers/promo.dart';
import '../../payments/payment_timeline.dart';
import '../../payments/wallet_insight.dart';
import '../../transporter/transporter_logic.dart';

/// One step of "when will I get my money" with how many trips or requests are
/// in it and how much (paise).
class HubStage {
  final String key;
  final int count;
  final int paise;
  const HubStage(this.key, this.count, this.paise);
}

DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

/// Weeks start on Monday 00:00 local time (the same as the older earnings view).
DateTime _startOfWeek(DateTime now) {
  final today = _startOfDay(now);
  return today.subtract(Duration(days: today.weekday - DateTime.monday));
}

/// The driver's figures (F9). Everything is worked out from the stored lines,
/// payouts and bookings; nothing here reads or writes Firestore.
class DriverHub {
  /// Available, held (asked for payout) and paid out, from the lines only.
  final WalletBalance balance;

  /// Delivered trips whose money has not come in yet.
  final int pendingPaise;

  /// Net of earnings, commission and corrections booked today / since Monday.
  final int todayPaise;
  final int weekPaise;

  /// The "paisa kab milega" steps, in the order money moves; empty steps are kept
  /// so the screen shows the whole road.
  final List<HubStage> stages;
  final List<Payout> payouts;
  final List<LedgerEntry> entries;

  const DriverHub({
    required this.balance,
    required this.pendingPaise,
    required this.todayPaise,
    required this.weekPaise,
    required this.stages,
    required this.payouts,
    required this.entries,
  });

  bool get isEmpty => entries.isEmpty && payouts.isEmpty && pendingPaise == 0;

  factory DriverHub.from({
    Iterable<LedgerEntry> entries = const [],
    Iterable<Booking> bookings = const [],
    Iterable<Payout> payouts = const [],
    required DateTime now,
  }) {
    final lines = entries.toList()
      ..sort((a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
    final pays = payouts.toList()
      ..sort((a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
    final book = WalletBook.fromSources(ledger: lines, payouts: pays);
    final waiting = WalletInsight.waiting(bookings);
    final customerToPay = waiting.where((w) => w.next == PaymentNext.waitCustomer).toList();
    final toConfirm = waiting.where((w) => w.next == PaymentNext.confirmReceived).toList();
    final open = pays.where((p) => p.isOpen).toList();

    final dayStart = _startOfDay(now), weekStart = _startOfWeek(now);
    var today = Money.zero, week = Money.zero;
    for (final e in lines) {
      final at = e.createdAt;
      if (at == null) continue;
      if (e.type != LedgerType.tripEarning && e.type != LedgerType.platformCommission && e.type != LedgerType.adjustment) continue;
      final m = Money(e.amountPaise).clamped;
      if (!at.isBefore(dayStart) && at.isBefore(dayStart.add(const Duration(days: 1)))) today = today + m;
      if (!at.isBefore(weekStart)) week = week + m;
    }
    int sum(Iterable<WaitingTrip> w) => w.fold(0, (a, b) => a + b.amountPaise);
    return DriverHub(
      balance: book.balance,
      pendingPaise: sum(waiting),
      todayPaise: today.paise,
      weekPaise: week.paise,
      stages: [
        HubStage('hubStageCustomer', customerToPay.length, sum(customerToPay)),
        HubStage('hubStageConfirm', toConfirm.length, sum(toConfirm)),
        HubStage('hubStageAvailable', book.balance.available.paise > 0 ? 1 : 0, book.balance.available.paise),
        HubStage('hubStageRequested', open.length, open.fold(0, (a, p) => a + p.amountPaise)),
        HubStage('hubStagePaid', pays.where((p) => p.status == Payout.paid).length, book.balance.paidOut.paise),
      ],
      payouts: pays,
      entries: lines,
    );
  }
}

/// The customer's figures: credits, what was spent, charges paid, credit records.
class CustomerHub {
  final int creditsPaise;
  final int spentMonthPaise;
  final int spentTotalPaise;
  final int deliveredTrips;

  /// Cancellation charges the customer paid (booking, charge).
  final List<(Booking, int)> charges;

  /// Credit lines, newest first (promo, referral, spend, admin grant or refund).
  final List<CreditLine> credits;

  const CustomerHub({
    required this.creditsPaise,
    required this.spentMonthPaise,
    required this.spentTotalPaise,
    required this.deliveredTrips,
    required this.charges,
    required this.credits,
  });

  bool get isEmpty => credits.isEmpty && deliveredTrips == 0 && charges.isEmpty;

  factory CustomerHub.from({Iterable<Booking> bookings = const [], Iterable<CreditLine> credits = const [], required DateTime now}) {
    var month = Money.zero, total = Money.zero, trips = 0;
    final charges = <(Booking, int)>[];
    for (final b in bookings) {
      if (b.status == BookingStatus.delivered) {
        final p = Money(b.billAmountPaise ?? 0).clamped;
        trips++;
        total = total + p;
        final at = b.timeline[BookingStatus.delivered] ?? b.createdAt?.toDate();
        if (at != null && at.year == now.year && at.month == now.month) month = month + p;
      }
      final c = b.cancellation;
      if (b.status == BookingStatus.cancelled && c != null && c.by == 'customer' && c.chargePaise > 0) charges.add((b, c.chargePaise));
    }
    final lines = credits.toList()
      ..sort((a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
    return CustomerHub(
      creditsPaise: Money(CreditLine.balance(lines)).clamped.atLeastZero.paise,
      spentMonthPaise: month.paise,
      spentTotalPaise: total.paise,
      deliveredTrips: trips,
      charges: charges,
      credits: lines,
    );
  }
}

/// One party line in the transporter's hub.
class PartyLine {
  final String partyId;
  final String name;
  final int trips;
  final int revenuePaise;
  final int receivedPaise;
  final int duePaise;
  final int marginPaise;
  const PartyLine(this.partyId, this.name, this.trips, this.revenuePaise, this.receivedPaise, this.duePaise, this.marginPaise);
}

/// The transporter's figures: totals and a ledger per party with the margin.
class TransporterHub {
  final int revenuePaise;
  final int marginPaise;
  final int dueFromPartiesPaise;
  final List<PartyLine> parties;

  const TransporterHub({required this.revenuePaise, required this.marginPaise, required this.dueFromPartiesPaise, required this.parties});

  bool get isEmpty => parties.isEmpty;

  factory TransporterHub.from(Iterable<TripAccount> accounts) {
    final books = TransporterBooks.from(accounts);
    final margin = <String, Money>{};
    for (final a in books.accounts) {
      margin[a.partyId] = (margin[a.partyId] ?? Money.zero) + Money(a.marginPaise).clamped;
    }
    return TransporterHub(
      revenuePaise: Money(books.revenuePaise).clamped.paise,
      marginPaise: Money(books.marginPaise).clamped.paise,
      dueFromPartiesPaise: Money(books.dueFromPartiesPaise).clamped.paise,
      parties: [
        for (final p in books.parties) PartyLine(p.partyId, p.partyName, p.trips, p.revenuePaise, p.receivedPaise, p.duePaise, (margin[p.partyId] ?? Money.zero).paise),
      ],
    );
  }
}
