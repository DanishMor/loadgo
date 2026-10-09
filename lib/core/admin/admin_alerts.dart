import 'staff_roles.dart';

enum AlertLevel { critical, warning, info }

/// One line of the alerts center (MASTER-6 Task 14).
class AdminAlert {
  /// sos, fraud, signals, strikes, held, docs, deletions.
  final String id;
  final AlertLevel level;
  final int count;

  /// The panel area (`staffAreas` key) that works on it; only staff who can
  /// use that area see the alert.
  final String area;

  /// For `docs`: the day with the most papers running out, and how many.
  final DateTime? peakDay;
  final int peakCount;
  const AdminAlert({required this.id, required this.level, required this.count, required this.area, this.peakDay, this.peakCount = 0});
}

class AdminAlerts {
  AdminAlerts._();

  /// Strikes at which a person shows in the alerts (the ladder asks for a review from 5).
  static const strikeAlertFrom = 3;

  /// Papers expiring on one day beyond this many count as a cluster.
  static const clusterFrom = 5;

  /// How far ahead expiring papers are looked at.
  static const docWindowDays = 14;

  /// The day (midnight) with the most papers, among [expiries] inside the next
  /// [docWindowDays] days of [now]; null when none. [total] counts all in the window.
  static ({DateTime day, int count, int total})? busiestExpiryDay(Iterable<DateTime> expiries, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final end = today.add(const Duration(days: docWindowDays + 1));
    final perDay = <DateTime, int>{};
    var total = 0;
    for (final e in expiries) {
      final d = DateTime(e.year, e.month, e.day);
      if (d.isBefore(today) || !d.isBefore(end)) continue;
      perDay[d] = (perDay[d] ?? 0) + 1;
      total++;
    }
    if (perDay.isEmpty) return null;
    final best = perDay.entries.reduce((a, b) => b.value > a.value || (b.value == a.value && b.key.isBefore(a.key)) ? b : a);
    return (day: best.key, count: best.value, total: total);
  }

  /// The alerts for [role], most urgent first. Alerts with a zero count are
  /// left out; one the role cannot work on is hidden.
  static List<AdminAlert> build({
    required String? role,
    int openSos = 0,
    int openFraudCases = 0,
    int unreviewedSignals = 0,
    int strikeUsers = 0,
    int heldUsers = 0,
    int pendingDeletions = 0,
    ({DateTime day, int count, int total})? docs,
  }) {
    final all = <AdminAlert>[
      if (openSos > 0) AdminAlert(id: 'sos', level: AlertLevel.critical, count: openSos, area: 'adminSos'),
      if (openFraudCases > 0) AdminAlert(id: 'fraud', level: AlertLevel.critical, count: openFraudCases, area: 'adminFraudCases'),
      if (unreviewedSignals > 0) AdminAlert(id: 'signals', level: AlertLevel.warning, count: unreviewedSignals, area: 'adminSignals'),
      if (strikeUsers > 0) AdminAlert(id: 'strikes', level: AlertLevel.warning, count: strikeUsers, area: 'pcAdminViolations'),
      if (docs != null && docs.total > 0)
        AdminAlert(id: 'docs', level: docs.count >= clusterFrom ? AlertLevel.warning : AlertLevel.info, count: docs.total, area: 'adminVehicles', peakDay: docs.day, peakCount: docs.count),
      if (heldUsers > 0) AdminAlert(id: 'held', level: AlertLevel.info, count: heldUsers, area: 'flaggedUsers'),
      if (pendingDeletions > 0) AdminAlert(id: 'deletions', level: AlertLevel.info, count: pendingDeletions, area: 'adminDeletionRequests'),
    ];
    final mine = [for (final a in all) if (staffCan(role, a.area)) a];
    mine.sort((a, b) => a.level.index.compareTo(b.level.index));
    return mine;
  }
}
