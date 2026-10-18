/// How a load is offered to drivers (Part 4, `dispatchV2`). Old loads have no `mode` and are `instant`.
enum LoadMode {
  /// The customer sets the price; nearby drivers are asked in rings; the first valid accept wins.
  instant('instant'),

  /// A bid window opens; drivers send prices; the customer counters once and accepts one.
  bid('bid'),

  /// Pickup later; goes out as `instant` shortly before.
  scheduled('scheduled');

  final String value;
  const LoadMode(this.value);

  static LoadMode fromValue(Object? v) {
    for (final m in values) {
      if (m.value == v) return m;
    }
    return LoadMode.instant;
  }
}

/// The note chips a driver can put on a bid. Only these, never free text.
enum BidNote {
  onTheWay('on_the_way'),
  emptyReturn('empty_return'),
  loadingHelp('loading_help'),
  flexibleTime('flexible_time'),
  cleanTruck('clean_truck');

  final String value;
  const BidNote(this.value);

  /// The word list the rules accept.
  static List<String> get codes => [for (final n in values) n.value];

  static BidNote? fromValue(Object? v) {
    for (final n in values) {
      if (n.value == v) return n;
    }
    return null;
  }
}

/// What the rules of a bid are judged on.
class BidFacts {
  final int pricePaise;
  final double? rating;
  final bool verified;
  const BidFacts({required this.pricePaise, this.rating, this.verified = false});
}

/// The customer's own rule for taking a bid without looking (U14): at most [maxPaise],
/// the driver rated at least [minRating] and, when [verifiedOnly], a verified driver.
/// A driver with no rating yet passes only when [minRating] is 0.
class AutoAccept {
  final int maxPaise;
  final double minRating;
  final bool verifiedOnly;

  const AutoAccept({required this.maxPaise, this.minRating = 0, this.verifiedOnly = false});

  static const maxAllowedPaise = 100000000;

  /// Null for anything that is not a valid rule, so a damaged document never accepts a bid.
  static AutoAccept? fromMap(Object? m) {
    if (m is! Map) return null;
    final max = m['maxPaise'], min = m['minRating'], ver = m['verifiedOnly'];
    if (max is! num || max != max.toInt() || max <= 0 || max > maxAllowedPaise) return null;
    final minR = min is num ? min.toDouble() : 0.0;
    if (minR < 0 || minR > 5) return null;
    return AutoAccept(maxPaise: max.toInt(), minRating: minR, verifiedOnly: ver == true);
  }

  Map<String, Object> toMap() => {'maxPaise': maxPaise, 'minRating': minRating, 'verifiedOnly': verifiedOnly};

  bool accepts(BidFacts b) {
    if (b.pricePaise <= 0 || b.pricePaise > maxPaise) return false;
    if (verifiedOnly && !b.verified) return false;
    if (minRating > 0 && (b.rating == null || b.rating! < minRating)) return false;
    return true;
  }
}

/// `config/dispatch`: how the rings and times work. Every field is checked and falls back to
/// its default, so a damaged document can never make loads invisible or the timer absurd.
class DispatchConfig {
  /// Distance limits of the rings, ascending, in km.
  final List<int> ringsKm;

  /// Seconds after posting when each ring unlocks (same length as [ringsKm], ascending, first is 0).
  final List<int> ringDelaySeconds;
  final int acceptSeconds;
  final int bidWindowMinutes;

  /// Partial overrides by city (lower case), e.g. a big city with a smaller first ring.
  final Map<String, Map<String, dynamic>> cities;

  const DispatchConfig({
    this.ringsKm = const [3, 7, 15],
    this.ringDelaySeconds = const [0, 30, 60],
    this.acceptSeconds = 30,
    this.bidWindowMinutes = 10,
    this.cities = const {},
  });

  static const defaults = DispatchConfig();

  static List<int>? _ascending(Object? v, {required int min, required int max, bool startsAtZero = false}) {
    if (v is! List || v.length < 2 || v.length > 5) return null;
    final out = <int>[];
    for (final e in v) {
      if (e is! num || e != e.toInt()) return null;
      final n = e.toInt();
      if (n < min || n > max) return null;
      if (out.isNotEmpty && n <= out.last) return null;
      out.add(n);
    }
    if (startsAtZero && out.first != 0) return null;
    return out;
  }

  factory DispatchConfig.fromMap(Map<String, dynamic>? m, {DispatchConfig base = defaults}) {
    if (m == null) return base;
    var rings = _ascending(m['ringsKm'], min: 1, max: 200) ?? base.ringsKm;
    var delays = _ascending(m['ringDelaySeconds'], min: 0, max: 600, startsAtZero: true) ?? base.ringDelaySeconds;
    // One delay for every ring; if the two lists disagree the safe default pair is used.
    if (rings.length != delays.length) {
      rings = base.ringsKm;
      delays = base.ringDelaySeconds;
    }
    int bounded(Object? v, int min, int max, int fallback) => v is num && v == v.toInt() && v >= min && v <= max ? v.toInt() : fallback;
    final cities = <String, Map<String, dynamic>>{};
    final raw = m['cities'];
    if (raw is Map) {
      for (final e in raw.entries) {
        if (e.key is String && e.value is Map && cities.length < 50) cities[(e.key as String).trim().toLowerCase()] = Map<String, dynamic>.from(e.value as Map);
      }
    }
    return DispatchConfig(
      ringsKm: rings,
      ringDelaySeconds: delays,
      acceptSeconds: bounded(m['acceptSeconds'], 10, 120, base.acceptSeconds),
      bidWindowMinutes: bounded(m['bidWindowMinutes'], 1, 60, base.bidWindowMinutes),
      cities: cities,
    );
  }

  /// The settings for a pickup city: the city's override on top of the general ones.
  DispatchConfig forCity(String? city) {
    final o = city == null ? null : cities[city.trim().toLowerCase()];
    if (o == null) return this;
    final merged = DispatchConfig.fromMap(o, base: DispatchConfig(ringsKm: ringsKm, ringDelaySeconds: ringDelaySeconds, acceptSeconds: acceptSeconds, bidWindowMinutes: bidWindowMinutes));
    return DispatchConfig(ringsKm: merged.ringsKm, ringDelaySeconds: merged.ringDelaySeconds, acceptSeconds: merged.acceptSeconds, bidWindowMinutes: merged.bidWindowMinutes);
  }
}
