/// E4: limits for a paid-capable adapter. The app-side guard stops a runaway loop on one phone;
/// the server repeats the same caps before any paid call (docs/CONNECT_*.md).
class CostCaps {
  /// Calls per day from this phone for all users together.
  final int daily;

  /// Calls per day for one user.
  final int perUser;
  const CostCaps({required this.daily, required this.perUser}) : assert(daily > 0 && perUser > 0 && perUser <= daily);

  /// `config/providers.<id>.daily` / `.perUser` may lower the caps, never raise them.
  CostCaps lowered(Map<String, dynamic>? m) {
    int pick(Object? v, int max) => v is int && v > 0 && v < max ? v : max;
    final d = pick(m?['daily'], daily);
    return CostCaps(daily: d, perUser: pick(m?['perUser'], perUser < d ? perUser : d));
  }
}

enum CostDenied { killed, dailyCap, userCap }

class CostGuard {
  final CostCaps caps;

  /// True when the adapter's kill switch (its flag or a kill-switch group) is off.
  final bool Function() killed;
  final DateTime Function() _now;
  CostGuard(this.caps, {required this.killed, DateTime Function()? now}) : _now = now ?? DateTime.now;

  String _day = '';
  int _total = 0;
  final Map<String, int> _byUser = {};

  void _roll() {
    final n = _now();
    final d = '${n.year}-${n.month}-${n.day}';
    if (d != _day) {
      _day = d;
      _total = 0;
      _byUser.clear();
    }
  }

  /// Null when the call may go ahead; the call is then counted.
  CostDenied? take(String uid) {
    if (killed()) return CostDenied.killed;
    _roll();
    if (_total >= caps.daily) return CostDenied.dailyCap;
    final used = _byUser[uid] ?? 0;
    if (used >= caps.perUser) return CostDenied.userCap;
    _total++;
    // Bounded: at most caps.daily distinct users per day.
    _byUser[uid] = used + 1;
    return null;
  }

  int get usedToday {
    _roll();
    return _total;
  }
}
