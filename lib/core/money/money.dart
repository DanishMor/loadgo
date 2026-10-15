/// Money as whole paise (F7). Never a double. Safe on the web too, where an
/// int is a 53-bit number: every result is kept inside [Money.limit].
extension type const Money(int paise) {
  /// Largest amount that may exist in one place (Rs 10,000 crore). Sums are
  /// clamped to this, so no addition can lose precision or wrap around.
  static const int limit = 1000000000000000; // 10^15 paise

  static const zero = Money(0);

  /// Whole rupees to paise (clamped).
  factory Money.rupees(int rupees) => Money(rupees * 100).clamped;

  /// From any number read out of a document: bad types, NaN, infinity and
  /// out-of-range values become 0 or the nearest limit, never an exception.
  static Money parse(Object? v) {
    if (v is int) return Money(v).clamped;
    if (v is double) {
      if (v.isNaN || v.isInfinite) return zero;
      return Money(v.round()).clamped;
    }
    return zero;
  }

  Money get clamped => Money(paise > limit ? limit : (paise < -limit ? -limit : paise));

  Money operator +(Money o) => Money(paise + o.paise).clamped;
  Money operator -(Money o) => Money(paise - o.paise).clamped;
  Money operator -() => Money(-paise);

  bool get isZero => paise == 0;
  bool get isNegative => paise < 0;
  bool operator <(Money o) => paise < o.paise;
  bool operator >(Money o) => paise > o.paise;
  bool operator <=(Money o) => paise <= o.paise;
  bool operator >=(Money o) => paise >= o.paise;

  Money get abs => Money(paise < 0 ? -paise : paise);

  /// Never below zero.
  Money get atLeastZero => paise < 0 ? zero : this;

  /// [bp] basis points of this amount (100 bp = 1%), rounded half away from
  /// zero, with integer maths only. [applyBp] of a negative amount is the
  /// mirror of the positive one.
  Money applyBp(int bp) {
    if (bp == 0 || paise == 0) return zero;
    final a = paise < 0 ? -paise : paise;
    final b = bp < 0 ? -bp : bp;
    // a * b can pass 2^53 on the web: split a into high and low parts.
    final hi = a ~/ 10000, lo = a % 10000;
    final q = hi * b + (lo * b + 5000) ~/ 10000;
    final neg = (paise < 0) != (bp < 0);
    return Money(neg ? -q : q).clamped;
  }

  /// Splits into (part, rest) where part is [bp] basis points. part + rest
  /// is always exactly this amount.
  (Money, Money) splitBp(int bp) {
    final part = applyBp(bp);
    return (part, this - part);
  }

  /// For logs and tests only (screens use the language-aware formatter).
  String get debug {
    final a = abs.paise;
    return '${paise < 0 ? '-' : ''}Rs ${a ~/ 100}.${(a % 100).toString().padLeft(2, '0')}';
  }
}
