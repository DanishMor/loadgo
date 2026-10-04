import '../analytics/trip_stats.dart' show routeKey;
import '../constants/logistics.dart';
import '../models/booking.dart';
import '../models/enterprise.dart';
import '../models/load.dart';

class RouteRow {
  final String route;
  final int loads;
  final int delivered;
  final int spendPaise;
  const RouteRow(this.route, this.loads, this.delivered, this.spendPaise);
}

class BranchRow {
  final String branch;
  final int loads;
  final int delivered;
  final int spendPaise;
  const BranchRow(this.branch, this.loads, this.delivered, this.spendPaise);
}

class DriverRow {
  final String driver;
  final int trips;
  final int delivered;
  final int spendPaise;
  const DriverRow(this.driver, this.trips, this.delivered, this.spendPaise);
}

/// Loads, deliveries and spend per route, per branch and per driver.
class RouteReport {
  final List<RouteRow> routes;
  final List<BranchRow> branches;
  final List<DriverRow> drivers;
  final int totalLoads;
  final int totalSpendPaise;

  const RouteReport(this.routes, this.branches, this.totalLoads, this.totalSpendPaise, [this.drivers = const []]);

  /// A load belongs to a branch through `branchId` (set when posting from a
  /// branch). Deleted branches are shown as the raw id.
  factory RouteReport.from(Iterable<Load> loads, Iterable<Booking> bookings, Iterable<Branch> branches) {
    final byLoad = {for (final b in bookings) b.loadId: b};
    final names = {for (final b in branches) b.id: b.name};
    final routes = <String, List<int>>{}; // [loads, delivered, spend]
    final perBranch = <String, List<int>>{};
    final perDriver = <String, List<int>>{};
    var total = 0;
    for (final l in loads) {
      final b = byLoad[l.id];
      final done = b != null && b.status == BookingStatus.delivered;
      final spend = done ? (b.billAmountPaise ?? 0) : 0;
      total += spend;
      final r = routes.putIfAbsent(routeKey(l.pickup, l.drop), () => [0, 0, 0]);
      r[0]++;
      if (done) r[1]++;
      r[2] += spend;
      if (b != null) {
        final name = b.driverName.isNotEmpty ? b.driverName : b.driverId;
        final d = perDriver.putIfAbsent(name, () => [0, 0, 0]);
        d[0]++;
        if (done) d[1]++;
        d[2] += spend;
      }
      final branchId = l.branchId;
      if (branchId != null) {
        final br = perBranch.putIfAbsent(names[branchId] ?? branchId, () => [0, 0, 0]);
        br[0]++;
        if (done) br[1]++;
        br[2] += spend;
      }
    }
    int cmp(String an, List<int> a, String bn, List<int> b) => b[0] != a[0] ? b[0].compareTo(a[0]) : an.compareTo(bn);
    final routeList = routes.entries.toList()..sort((a, b) => cmp(a.key, a.value, b.key, b.value));
    final branchList = perBranch.entries.toList()..sort((a, b) => cmp(a.key, a.value, b.key, b.value));
    final driverList = perDriver.entries.toList()..sort((a, b) => cmp(a.key, a.value, b.key, b.value));
    return RouteReport(
      [for (final e in routeList) RouteRow(e.key, e.value[0], e.value[1], e.value[2])],
      [for (final e in branchList) BranchRow(e.key, e.value[0], e.value[1], e.value[2])],
      loads.length,
      total,
      [for (final e in driverList) DriverRow(e.key, e.value[0], e.value[1], e.value[2])],
    );
  }

  /// CSV text for sharing or pasting into a sheet. Spend in rupees.
  String toCsv() {
    String rupees(int paise) => (paise / 100).toStringAsFixed(2);
    String cell(String s) => s.contains(',') || s.contains('"') ? '"${s.replaceAll('"', '""')}"' : s;
    return [
      'Route,Loads,Delivered,Spend (INR)',
      for (final r in routes) '${cell(r.route)},${r.loads},${r.delivered},${rupees(r.spendPaise)}',
      '',
      'Branch,Loads,Delivered,Spend (INR)',
      for (final b in branches) '${cell(b.branch)},${b.loads},${b.delivered},${rupees(b.spendPaise)}',
      '',
      'Driver,Trips,Delivered,Spend (INR)',
      for (final d in drivers) '${cell(d.driver)},${d.trips},${d.delivered},${rupees(d.spendPaise)}',
    ].join('\n');
  }
}
