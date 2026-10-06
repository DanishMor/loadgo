import '../constants/logistics.dart';
import 'booking.dart';
import 'earnings.dart';

/// `business_invites/{ownerId}_{digits}`: a company owner invites a team
/// member (booker) by phone number.
class BusinessInvite {
  final String id;
  final String ownerId;
  final String ownerName;
  final String phone;
  final String status;
  final String role;

  const BusinessInvite({required this.id, required this.ownerId, this.ownerName = '', required this.phone, required this.status, this.role = BusinessMember.booker});

  static const pending = 'pending';
  static const accepted = 'accepted';
  static const declined = 'declined';
  static const cancelled = 'cancelled';

  factory BusinessInvite.fromDoc(String id, Map<String, dynamic> d) => BusinessInvite(
        id: id,
        ownerId: d['ownerId'] as String? ?? '',
        ownerName: d['ownerName'] as String? ?? '',
        phone: d['phone'] as String? ?? '',
        status: d['status'] as String? ?? pending,
        role: d['role'] as String? ?? BusinessMember.booker,
      );
}

/// `business_members/{ownerId}_{memberUid}`: a booker who may post loads for
/// the company.
class BusinessMember {
  static const booker = 'booker';

  final String id;
  final String ownerId;
  final String ownerName;
  final String memberId;
  final String memberName;
  final String memberPhone;
  final String role;
  final bool active;

  const BusinessMember({
    required this.id,
    required this.ownerId,
    this.ownerName = '',
    required this.memberId,
    this.memberName = '',
    this.memberPhone = '',
    this.role = booker,
    required this.active,
  });

  factory BusinessMember.fromDoc(String id, Map<String, dynamic> d) => BusinessMember(
        id: id,
        ownerId: d['ownerId'] as String? ?? '',
        ownerName: d['ownerName'] as String? ?? '',
        memberId: d['memberId'] as String? ?? '',
        memberName: d['memberName'] as String? ?? '',
        memberPhone: d['memberPhone'] as String? ?? '',
        role: d['role'] as String? ?? booker,
        active: d['active'] == true,
      );
}

/// One company's delivered trips in a month, grouped by cost centre. Money is
/// integer paise (paid > agreed > estimate); it is a record, not an invoice.
class MonthlyStatement {
  static const noCostCenter = '';

  /// `yyyy-MM`.
  final String month;
  final int trips;
  final int totalPaise;

  /// Cost centre -> paise ('' = untagged).
  final Map<String, int> byCostCenter;

  /// Delivered bookings of the month, oldest first.
  final List<Booking> bookings;

  const MonthlyStatement({required this.month, required this.trips, required this.totalPaise, required this.byCostCenter, required this.bookings});

  static String monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

  factory MonthlyStatement.from(Iterable<Booking> bookings, DateTime month) {
    final key = monthKey(month);
    final inMonth = bookings.where((b) => b.status == BookingStatus.delivered && monthKey(EarningsSummary.deliveredAt(b)) == key).toList()
      ..sort((a, b) => EarningsSummary.deliveredAt(a).compareTo(EarningsSummary.deliveredAt(b)));
    final by = <String, int>{};
    var total = 0;
    for (final b in inMonth) {
      final p = b.billAmountPaise ?? 0;
      total += p;
      by.update(b.costCenter ?? noCostCenter, (v) => v + p, ifAbsent: () => p);
    }
    return MonthlyStatement(month: key, trips: inMonth.length, totalPaise: total, byCostCenter: by, bookings: inMonth);
  }

  /// Cost centres, biggest spend first, untagged last.
  List<MapEntry<String, int>> get sortedCenters {
    final l = byCostCenter.entries.toList();
    l.sort((a, b) {
      if (a.key.isEmpty != b.key.isEmpty) return a.key.isEmpty ? 1 : -1;
      return b.value.compareTo(a.value);
    });
    return l;
  }

  /// One line per trip, for copying into a spreadsheet.
  String toCsv() {
    String q(String s) => '"${s.replaceAll('"', '""')}"';
    final rows = <String>['date,cost_center,from,to,vehicle,amount_rupees'];
    for (final b in bookings) {
      final d = EarningsSummary.deliveredAt(b);
      final p = b.billAmountPaise ?? 0;
      rows.add([
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
        q(b.costCenter ?? ''),
        q(b.pickup),
        q(b.drop),
        q(b.vehicleNumber),
        '${p ~/ 100}.${(p % 100).toString().padLeft(2, '0')}',
      ].join(','));
    }
    return rows.join('\n');
  }
}
