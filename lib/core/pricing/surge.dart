/// Peak, night and festival surge, set by an admin in `config/pricing` under
/// `surge`. OFF by default. Percent values are whole percents of the base
/// freight; the sum of the windows active at a time is capped at [capPercent].
library;

class SurgeKind {
  SurgeKind._();
  static const none = '';
  static const peak = 'peak';
  static const night = 'night';
  static const festival = 'festival';
}

/// Hours of the day: [startHour] inclusive to [endHour] exclusive. When
/// [startHour] is after [endHour] the window wraps past midnight (22 to 5).
/// Equal hours mean the window is off.
class SurgeWindow {
  final int startHour;
  final int endHour;
  final int percent;

  const SurgeWindow({required this.startHour, required this.endHour, required this.percent});

  bool contains(int hour) {
    if (percent <= 0 || startHour == endHour) return false;
    return startHour < endHour ? hour >= startHour && hour < endHour : hour >= startHour || hour < endHour;
  }

  factory SurgeWindow.fromMap(Object? raw, SurgeWindow fallback) {
    if (raw is! Map) return fallback;
    int hour(Object? v, int f) => v is num && v >= 0 && v <= 24 ? v.round() % 24 : f;
    final p = raw['percent'];
    return SurgeWindow(
      startHour: hour(raw['startHour'], fallback.startHour),
      endHour: hour(raw['endHour'], fallback.endHour),
      percent: p is num && p >= 0 ? p.round() : fallback.percent,
    );
  }

  Map<String, int> toMap() => {'startHour': startHour, 'endHour': endHour, 'percent': percent};
}

/// A festival period, whole days from [from] to [to] inclusive.
class FestivalRange {
  final DateTime from;
  final DateTime to;
  final int percent;
  final String name;

  const FestivalRange({required this.from, required this.to, required this.percent, this.name = ''});

  bool contains(DateTime t) {
    if (percent <= 0) return false;
    final d = DateTime(t.year, t.month, t.day);
    return !d.isBefore(from) && !d.isAfter(to);
  }

  static DateTime? _date(Object? v) {
    if (v is! String) return null;
    final d = DateTime.tryParse(v);
    return d == null ? null : DateTime(d.year, d.month, d.day);
  }

  static FestivalRange? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final from = _date(raw['from']), to = _date(raw['to']);
    final p = raw['percent'];
    if (from == null || to == null || to.isBefore(from) || p is! num || p <= 0) return null;
    final name = raw['name'];
    return FestivalRange(from: from, to: to, percent: p.round(), name: name is String ? name : '');
  }

  Map<String, Object> toMap() => {'from': _fmt(from), 'to': _fmt(to), 'percent': percent, 'name': name};

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class SurgeRule {
  final bool enabled;
  final SurgeWindow peak;
  final SurgeWindow night;
  final List<FestivalRange> festivals;

  /// Highest total surge, in percent.
  final int capPercent;

  const SurgeRule({
    this.enabled = false,
    this.peak = const SurgeWindow(startHour: 8, endHour: 11, percent: 10),
    this.night = const SurgeWindow(startHour: 22, endHour: 5, percent: 15),
    this.festivals = const [],
    this.capPercent = 30,
  });

  static const off = SurgeRule();

  factory SurgeRule.fromMap(Object? raw) {
    if (raw is! Map) return off;
    const d = SurgeRule();
    final cap = raw['capPercent'];
    return SurgeRule(
      enabled: raw['enabled'] == true,
      peak: SurgeWindow.fromMap(raw['peak'], d.peak),
      night: SurgeWindow.fromMap(raw['night'], d.night),
      festivals: [
        for (final f in (raw['festivals'] is List ? raw['festivals'] as List : const [])) ?FestivalRange.tryParse(f),
      ],
      capPercent: cap is num && cap >= 0 ? cap.round() : d.capPercent,
    );
  }

  Map<String, Object> toMap() => {
        'enabled': enabled,
        'peak': peak.toMap(),
        'night': night.toMap(),
        'festivals': [for (final f in festivals) f.toMap()],
        'capPercent': capPercent,
      };
}

/// What applies at one moment.
class SurgeQuote {
  final int percent;

  /// A [SurgeKind] value: the window that adds the most (festival wins a tie).
  final String kind;

  const SurgeQuote(this.percent, this.kind);

  static const none = SurgeQuote(0, SurgeKind.none);

  bool get active => percent > 0;
}

class SurgeCalculator {
  SurgeCalculator._();

  static SurgeQuote at(DateTime t, SurgeRule rule) {
    if (!rule.enabled) return SurgeQuote.none;
    var sum = 0;
    var best = 0;
    var kind = SurgeKind.none;
    void add(int percent, String k) {
      sum += percent;
      if (percent >= best) {
        best = percent;
        kind = k;
      }
    }

    if (rule.peak.contains(t.hour)) add(rule.peak.percent, SurgeKind.peak);
    if (rule.night.contains(t.hour)) add(rule.night.percent, SurgeKind.night);
    for (final f in rule.festivals) {
      if (f.contains(t)) add(f.percent, SurgeKind.festival);
    }
    final capped = sum > rule.capPercent ? rule.capPercent : sum;
    return capped <= 0 ? SurgeQuote.none : SurgeQuote(capped, kind);
  }

  static int percentAt(DateTime t, SurgeRule rule) => at(t, rule).percent;
}
