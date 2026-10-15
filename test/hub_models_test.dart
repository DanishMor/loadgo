import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/ledger_entry.dart';
import 'package:transport_app/core/models/payout.dart';
import 'package:transport_app/core/offers/promo.dart';
import 'package:transport_app/core/transporter/transporter_logic.dart';
import 'package:transport_app/core/wallet/hub/hub_models.dart';

/// F9: the numbers behind the three hubs.
void main() {
  final now = DateTime(2026, 10, 14, 15); // a Wednesday
  Booking booking(String id, String status, {String payment = 'pending', int? fare, Map<String, DateTime> timeline = const {}, BookingCancellation? cancel}) => Booking(
        id: id, loadId: 'L', driverId: 'd1', vehicleId: 'v', customerId: 'c1', status: status, pickup: 'Pune', drop: 'Delhi',
        cargoType: 'x', weight: 1, vehicleType: '20ft', budget: null, pickupDate: null, notes: '', vehicleNumber: 'MH12AB1',
        driverName: 'Ravi', driverPhone: '', timeline: timeline, paymentStatus: payment, paidAmountPaise: fare, cancellation: cancel,
      );
  LedgerEntry line(String id, String type, int a, DateTime at) => LedgerEntry(id: id, driverId: 'd1', bookingId: id.split('_').first, type: type, amountPaise: a, createdAt: at);

  group('DriverHub', () {
    test('today, this week (from Monday), available, held, paid out', () {
      final hub = DriverHub.from(now: now, entries: [
        line('B1_trip_earning', LedgerType.tripEarning, 100000, DateTime(2026, 10, 14, 9)), // today
        line('B1_platform_commission', LedgerType.platformCommission, -10000, DateTime(2026, 10, 14, 9)),
        line('B2_trip_earning', LedgerType.tripEarning, 50000, DateTime(2026, 10, 12, 18)), // Monday
        line('B3_trip_earning', LedgerType.tripEarning, 70000, DateTime(2026, 10, 11, 23, 59)), // last Sunday
        line('adj_1', LedgerType.adjustment, -2000, DateTime(2026, 10, 13, 10)),
      ], payouts: [
        const Payout(id: 'p1', driverId: 'd1', amountPaise: 30000, status: Payout.requested),
        const Payout(id: 'p2', driverId: 'd1', amountPaise: 20000, status: Payout.paid),
      ]);
      expect(hub.todayPaise, 90000);
      expect(hub.weekPaise, 90000 + 50000 - 2000);
      expect(hub.balance.held.paise, 30000);
      expect(hub.balance.paidOut.paise, 20000);
      expect(hub.balance.available.paise, 100000 - 10000 + 50000 + 70000 - 2000 - 30000 - 20000);
      expect(hub.isEmpty, isFalse);
    });

    test('the road of the money has the five steps in order, empty ones kept', () {
      final hub = DriverHub.from(now: now);
      expect(hub.stages.map((s) => s.key), ['hubStageCustomer', 'hubStageConfirm', 'hubStageAvailable', 'hubStageRequested', 'hubStagePaid']);
      expect(hub.stages.every((s) => s.count == 0 && s.paise == 0), isTrue);
      expect(hub.isEmpty, isTrue);
    });

    test('delivered trips wait for the customer, then for the driver to confirm', () {
      final hub = DriverHub.from(now: now, bookings: [
        booking('b1', BookingStatus.delivered, fare: 40000),
        booking('b2', BookingStatus.delivered, payment: PaymentStatus.customerMarkedPaid, fare: 25000),
        booking('b3', BookingStatus.delivered, payment: PaymentStatus.driverConfirmed, fare: 99999),
        booking('b4', BookingStatus.inTransit, fare: 12345),
      ]);
      expect(hub.pendingPaise, 65000);
      expect(hub.stages[0].count, 1);
      expect(hub.stages[0].paise, 40000);
      expect(hub.stages[1].count, 1);
      expect(hub.stages[1].paise, 25000);
    });

    test('lines without a date and odd amounts never crash', () {
      final hub = DriverHub.from(now: now, entries: [
        const LedgerEntry(id: 'x_trip_earning', driverId: 'd', bookingId: 'x', type: LedgerType.tripEarning, amountPaise: 500),
        const LedgerEntry(id: 'y_other', driverId: 'd', bookingId: 'y', type: 'mystery', amountPaise: 999999),
      ]);
      expect(hub.todayPaise, 0);
      expect(hub.weekPaise, 0);
      expect(hub.balance.available.paise, 500);
    });
  });

  group('CustomerHub', () {
    test('credits never show below zero; spent this month and in total count delivered trips only', () {
      final hub = CustomerHub.from(now: now, bookings: [
        booking('b1', BookingStatus.delivered, fare: 100000, timeline: {BookingStatus.delivered: DateTime(2026, 10, 3)}),
        booking('b2', BookingStatus.delivered, fare: 50000, timeline: {BookingStatus.delivered: DateTime(2026, 9, 30)}),
        booking('b3', BookingStatus.inTransit, fare: 70000),
        booking('b4', BookingStatus.cancelled, cancel: const BookingCancellation(by: 'customer', chargePaise: 15000)),
        booking('b5', BookingStatus.cancelled, cancel: const BookingCancellation(by: 'driver', chargePaise: 9000)),
      ], credits: [
        CreditLine(id: 'c1', amountPaise: 20000, kind: 'referral', createdAt: DateTime(2026, 10, 1)),
        CreditLine(id: 'c2', amountPaise: -5000, kind: 'spend', createdAt: DateTime(2026, 10, 2)),
      ]);
      expect(hub.creditsPaise, 15000);
      expect(hub.spentMonthPaise, 100000);
      expect(hub.spentTotalPaise, 150000);
      expect(hub.deliveredTrips, 2);
      expect(hub.charges.length, 1);
      expect(hub.charges.single.$2, 15000);
      expect(hub.credits.first.id, 'c2', reason: 'newest first');
    });

    test('a negative credit balance shows as zero; nothing at all is empty', () {
      expect(CustomerHub.from(now: now, credits: [const CreditLine(id: 'c', amountPaise: -900, kind: 'admin_deduct')]).creditsPaise, 0);
      expect(CustomerHub.from(now: now).isEmpty, isTrue);
    });
  });

  group('TransporterHub', () {
    test('margin per party and in total, largest due first', () {
      final hub = TransporterHub.from([
        const TripAccount(bookingId: 'a', partyId: 'p1', partyName: 'Shree Traders', revenuePaise: 100000, driverPayPaise: 70000, otherCostPaise: 5000, receivedPaise: 40000),
        const TripAccount(bookingId: 'b', partyId: 'p1', partyName: 'Shree Traders', revenuePaise: 50000, driverPayPaise: 60000, receivedPaise: 50000),
        const TripAccount(bookingId: 'c', partyId: 'p2', partyName: 'Om Agro', revenuePaise: 30000, driverPayPaise: 20000, receivedPaise: 0),
      ]);
      expect(hub.revenuePaise, 180000);
      expect(hub.marginPaise, 25000 + (-10000) + 10000);
      expect(hub.dueFromPartiesPaise, 60000 + 30000);
      expect(hub.parties.first.partyId, 'p1');
      final p1 = hub.parties.firstWhere((p) => p.partyId == 'p1');
      expect(p1.trips, 2);
      expect(p1.marginPaise, 15000, reason: 'a loss on one trip lowers the party margin');
      expect(p1.duePaise, 60000);
      expect(hub.parties.firstWhere((p) => p.partyId == 'p2').marginPaise, 10000);
    });

    test('no accounts is empty', () {
      expect(TransporterHub.from(const []).isEmpty, isTrue);
    });
  });

  test('timestamps from Firestore are accepted by the ledger parser', () {
    expect(Timestamp.fromDate(now).toDate(), now);
  });
}
